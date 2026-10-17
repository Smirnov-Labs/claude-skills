# GitOps Workflow Patterns

Best practices and patterns for GitOps-based Kubernetes deployments with ArgoCD.

## Core GitOps Principles

1. **Git as Single Source of Truth**: All desired state in Git
2. **Declarative Configuration**: Describe what you want, not how to get there
3. **Automated Synchronization**: Tools automatically apply Git state to cluster
4. **Continuous Reconciliation**: Cluster state continuously reconciled with Git

## Repository Structures

### Pattern 1: Monorepo (All Apps in One Repo)

```
gitops-repo/
├── apps/
│   ├── api/
│   │   ├── base/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       ├── dev/
│   │       │   └── kustomization.yaml
│   │       ├── staging/
│   │       │   └── kustomization.yaml
│   │       └── production/
│   │           └── kustomization.yaml
│   ├── frontend/
│   └── worker/
├── infrastructure/
│   ├── ingress-nginx/
│   ├── cert-manager/
│   └── monitoring/
└── argocd/
    └── applications/
        ├── api-dev.yaml
        ├── api-staging.yaml
        └── api-production.yaml
```

**Pros:**
- Easy to see all applications
- Simple RBAC (one repo to protect)
- Easy to coordinate changes across apps

**Cons:**
- Can become large
- All teams have access to all apps (unless using CODEOWNERS)

### Pattern 2: Repo per Environment

```
gitops-dev/
├── api/
├── frontend/
└── worker/

gitops-staging/
├── api/
├── frontend/
└── worker/

gitops-production/
├── api/
├── frontend/
└── worker/
```

**Pros:**
- Clear environment separation
- Different RBAC per environment
- Production protected independently

**Cons:**
- Harder to see differences between environments
- More repos to manage

### Pattern 3: Repo per Team/Application

```
team-api-gitops/
├── base/
├── overlays/
│   ├── dev/
│   ├── staging/
│   └── production/
└── argocd/

team-frontend-gitops/
├── base/
├── overlays/
└── argocd/
```

**Pros:**
- Team autonomy
- Clear ownership
- Isolated changes

**Cons:**
- Cross-team coordination harder
- More ArgoCD applications to manage

## Kustomize Patterns

### Base + Overlays Structure

```
my-app/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── replica-count.yaml
    │   └── env-vars.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── production/
        └── kustomization.yaml
```

**base/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml
- configmap.yaml

commonLabels:
  app: my-app
  managed-by: argocd
```

**overlays/production/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- ../../base

namespace: my-app-prod

replicas:
- name: my-app
  count: 3

images:
- name: my-app
  newName: registry.example.com/my-app
  newTag: v1.2.3

patchesStrategicMerge:
- replica-count.yaml

configMapGenerator:
- name: app-config
  env: production.env
  behavior: merge
```

### Common Kustomize Patches

**Change replicas:**
```yaml
# replica-count.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 5
```

**Add resource limits:**
```yaml
# resources.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
```

**Add environment variables:**
```yaml
# env-vars.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: LOG_LEVEL
          value: "debug"
        - name: ENVIRONMENT
          value: "production"
```

## ArgoCD Application Patterns

### Pattern 1: App-of-Apps

One parent application that creates child applications.

**apps/app-of-apps.yaml:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/gitops-repo
    targetRevision: main
    path: argocd/applications
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**argocd/applications/api.yaml:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/gitops-repo
    targetRevision: main
    path: apps/api/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: api-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### Pattern 2: ApplicationSet

Generate multiple applications from templates.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: microservices
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - app: api
        namespace: api-prod
      - app: frontend
        namespace: frontend-prod
      - app: worker
        namespace: worker-prod

  template:
    metadata:
      name: '{{app}}-production'
    spec:
      project: default
      source:
        repoURL: https://github.com/org/gitops-repo
        targetRevision: main
        path: 'apps/{{app}}/overlays/production'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

### Pattern 3: Multi-Cluster with ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: api-multi-cluster
  namespace: argocd
spec:
  generators:
  - matrix:
      generators:
      - list:
          elements:
          - env: staging
            cluster: staging-cluster
          - env: production
            cluster: production-cluster
      - list:
          elements:
          - app: api
            namespace: api

  template:
    metadata:
      name: '{{app}}-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/org/gitops-repo
        targetRevision: main
        path: 'apps/{{app}}/overlays/{{env}}'
      destination:
        name: '{{cluster}}'
        namespace: '{{namespace}}-{{env}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## Deployment Strategies

### Blue-Green Deployment

Use two identical environments, switch traffic when ready.

```yaml
# blue deployment (current)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-blue
  labels:
    version: blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
      version: blue
  template:
    metadata:
      labels:
        app: api
        version: blue
    spec:
      containers:
      - name: api
        image: myapp:v1.0
---
# green deployment (new)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-green
  labels:
    version: green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
      version: green
  template:
    metadata:
      labels:
        app: api
        version: green
    spec:
      containers:
      - name: api
        image: myapp:v1.1
---
# service (switch by changing selector)
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    app: api
    version: blue  # Change to 'green' to switch
  ports:
  - port: 80
    targetPort: 8080
```

**Workflow:**
1. Deploy green alongside blue
2. Test green
3. Update service selector to green
4. Monitor
5. Delete blue deployment

### Canary Deployment with Sync Waves

```yaml
# Main deployment (90% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-stable
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  replicas: 9
  selector:
    matchLabels:
      app: api
      track: stable
  template:
    metadata:
      labels:
        app: api
        track: stable
    spec:
      containers:
      - name: api
        image: myapp:v1.0
---
# Canary deployment (10% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-canary
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
      track: canary
  template:
    metadata:
      labels:
        app: api
        track: canary
    spec:
      containers:
      - name: api
        image: myapp:v1.1
---
# Service (routes to both)
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    app: api  # Matches both stable and canary
  ports:
  - port: 80
    targetPort: 8080
```

## Promotion Workflows

### Manual Promotion Between Environments

```bash
# 1. Test in dev
cd gitops-repo
git checkout main

# Update dev overlay
cd apps/api/overlays/dev
kustomize edit set image myapp=myapp:v1.2.0
git add .
git commit -m "Update api to v1.2.0 in dev"
git push

# 2. Wait for ArgoCD sync and verify
argocd app wait api-dev --health

# 3. Promote to staging
cd ../staging
kustomize edit set image myapp=myapp:v1.2.0
git add .
git commit -m "Promote api v1.2.0 to staging"
git push

# 4. Verify staging
argocd app wait api-staging --health

# 5. Promote to production
cd ../production
kustomize edit set image myapp=myapp:v1.2.0
git add .
git commit -m "Promote api v1.2.0 to production"
git push

# 6. Monitor production
argocd app wait api-production --health
kubectl get pods -n api-prod -w
```

### Automated Promotion with PR

```bash
# CI pipeline creates promotion PR
name: Promote to Staging
on:
  push:
    branches:
      - main
    paths:
      - 'apps/*/overlays/dev/**'

jobs:
  promote:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2

    - name: Extract new image tag
      id: extract
      run: |
        TAG=$(yq e '.images[0].newTag' apps/api/overlays/dev/kustomization.yaml)
        echo "tag=$TAG" >> $GITHUB_OUTPUT

    - name: Update staging
      run: |
        cd apps/api/overlays/staging
        kustomize edit set image myapp=myapp:${{ steps.extract.outputs.tag }}

    - name: Create PR
      uses: peter-evans/create-pull-request@v4
      with:
        commit-message: "Promote api to ${{ steps.extract.outputs.tag }} in staging"
        title: "Promote api to staging"
        body: "Auto-generated promotion PR"
        branch: promote-staging-${{ steps.extract.outputs.tag }}
```

## Best Practices

### 1. Separate Config from Secrets

**Good:**
```yaml
# ConfigMap for non-sensitive data
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DATABASE_HOST: postgres.database.svc.cluster.local
  LOG_LEVEL: info
---
# Sealed Secret for sensitive data
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: app-secrets
spec:
  encryptedData:
    DATABASE_PASSWORD: AgBz8f7...  # Encrypted
```

### 2. Use Sync Waves for Dependencies

```yaml
# Database first (wave 0)
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-init
  annotations:
    argocd.argoproj.io/sync-wave: "0"
---
# Application second (wave 1)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  annotations:
    argocd.argoproj.io/sync-wave: "1"
---
# Ingress last (wave 2)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

### 3. Use Health Checks

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    spec:
      containers:
      - name: api
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

### 4. Resource Limits

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    spec:
      containers:
      - name: api
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
```

### 5. Use Labels Consistently

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels:
    app: api
    component: backend
    environment: production
    managed-by: argocd
    version: v1.2.0
spec:
  selector:
    matchLabels:
      app: api
      environment: production
  template:
    metadata:
      labels:
        app: api
        component: backend
        environment: production
        version: v1.2.0
```

## Debugging GitOps Workflows

### Check Git History

```bash
# Find recent changes
git log --oneline -20 -- apps/api/

# Show specific change
git show <commit-hash>

# Compare environments
git diff main:apps/api/overlays/dev/kustomization.yaml \
         main:apps/api/overlays/production/kustomization.yaml

# Find who changed what
git blame apps/api/overlays/production/kustomization.yaml
```

### Validate Before Pushing

```bash
# Build with kustomize
kustomize build apps/api/overlays/production

# Validate with kubectl
kustomize build apps/api/overlays/production | kubectl apply --dry-run=client -f -

# Check with kubeval
kustomize build apps/api/overlays/production | kubeval --strict
```

### Test Locally

```bash
# Build and apply to local cluster
kustomize build apps/api/overlays/dev | kubectl apply -f - --dry-run=server

# Create temporary namespace for testing
kubectl create namespace test-api
kustomize build apps/api/overlays/dev | kubectl apply -f - -n test-api

# Cleanup
kubectl delete namespace test-api
```

## Common Patterns

### Rolling Back a Deployment

```bash
# Option 1: Revert Git commit
git revert <bad-commit-hash>
git push
# ArgoCD will sync automatically

# Option 2: Update image tag to previous version
cd apps/api/overlays/production
kustomize edit set image myapp=myapp:v1.1.0  # Previous good version
git commit -am "Rollback to v1.1.0"
git push

# Option 3: Use ArgoCD rollback
argocd app rollback api-production <history-id>
# Then update Git to match
```

### Emergency Hotfix

```bash
# 1. Create hotfix branch
git checkout -b hotfix/critical-bug

# 2. Make fix
cd apps/api/overlays/production
# Update manifest
git commit -am "hotfix: critical bug fix"

# 3. Fast-track to production
git push origin hotfix/critical-bug

# 4. Update ArgoCD to use hotfix branch temporarily
argocd app set api-production --revision hotfix/critical-bug

# 5. Merge hotfix to main
git checkout main
git merge hotfix/critical-bug
git push

# 6. Set ArgoCD back to main
argocd app set api-production --revision main
```

## Monitoring GitOps Health

### Key Metrics to Track

1. **Sync Status**: Are apps in sync?
2. **Sync Duration**: How long do syncs take?
3. **Sync Failures**: How many syncs fail?
4. **Drift Detection**: Manual changes happening?
5. **Git Commit to Deploy Time**: How fast is deployment?

### ArgoCD Metrics Queries

```bash
# List out-of-sync apps
argocd app list --output json | jq '.[] | select(.status.sync.status == "OutOfSync") | .metadata.name'

# List degraded apps
argocd app list --output json | jq '.[] | select(.status.health.status == "Degraded") | .metadata.name'

# Check sync history
argocd app history api-production
```
