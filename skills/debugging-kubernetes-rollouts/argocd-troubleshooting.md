# ArgoCD Troubleshooting Guide

Comprehensive guide for debugging ArgoCD-specific issues in GitOps deployments.

## Understanding ArgoCD States

### Application Health States

- **Healthy**: All resources are healthy
- **Progressing**: Resources are being deployed
- **Degraded**: Some resources are unhealthy
- **Suspended**: Application is suspended
- **Missing**: Resources are missing from cluster
- **Unknown**: Health cannot be determined

### Application Sync States

- **Synced**: Git state matches cluster state
- **OutOfSync**: Git state differs from cluster state
- **Unknown**: Sync state cannot be determined

## Common ArgoCD Issues

### Issue 1: Application OutOfSync (But Nothing Changed)

**Symptoms:**
- ArgoCD shows OutOfSync
- No recent Git commits
- Resources appear correct in cluster

**Investigation:**

```bash
# Check what ArgoCD thinks is different
argocd app diff <app-name>

# Check for drift (manual changes)
argocd app diff <app-name> --local-repo-path=.

# Check resource tracking
argocd app get <app-name> --show-params
```

**Common Causes:**

1. **Manual kubectl changes**: Someone modified resources directly
   ```bash
   # Find resources with unexpected changes
   kubectl get deployment/<name> -n <namespace> -o yaml | grep -A 2 "kubectl.kubernetes.io"
   ```

2. **External controllers**: Other controllers (HPA, VPA) modifying resources
   ```bash
   # Check for HPA
   kubectl get hpa -n <namespace>

   # Check for VPA
   kubectl get vpa -n <namespace>
   ```

3. **Webhook mutations**: Admission webhooks modifying resources
   ```bash
   # Check mutating webhooks
   kubectl get mutatingwebhookconfigurations
   ```

4. **ArgoCD tracking method**: Label/annotation tracking misconfigured
   ```bash
   # Check tracking method
   argocd app get <app-name> | grep "Tracking Method"
   ```

**Solutions:**

```bash
# Option 1: Sync to Git state (overwrites cluster)
argocd app sync <app-name>

# Option 2: Accept cluster state (update Git if needed)
kubectl get deployment/<name> -n <namespace> -o yaml > current.yaml
# Review and update Git repo

# Option 3: Ignore differences for specific fields
# Add to application manifest:
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas  # Ignore HPA changes
```

### Issue 2: Sync Operation Failing

**Symptoms:**
- Sync button in UI doesn't work
- Sync hangs indefinitely
- Sync completes but resources not updated

**Investigation:**

```bash
# Check sync operation
argocd app get <app-name> --show-operation

# Check for errors
argocd app get <app-name> | grep -A 10 "Operation:"

# Check sync history
argocd app history <app-name>

# Check logs
argocd app logs <app-name>
```

**Common Causes:**

1. **Invalid manifest**: YAML syntax error in Git
   ```bash
   # Validate locally
   cd <gitops-repo>
   kubectl apply --dry-run=client -f deployment.yaml

   # Check ArgoCD can parse it
   argocd app manifests <app-name>
   ```

2. **Resource quota exceeded**: Can't create resources
   ```bash
   kubectl describe resourcequota -n <namespace>
   ```

3. **Pre-sync hook failing**: Hook not completing
   ```bash
   # Check for hooks
   grep -r "argocd.argoproj.io/hook" <gitops-repo>

   # View hook status
   argocd app get <app-name> | grep -A 5 "Resource Hooks"
   ```

4. **RBAC issues**: ArgoCD can't modify resources
   ```bash
   # Check ArgoCD service account permissions
   kubectl auth can-i create deployments --as=system:serviceaccount:argocd:argocd-application-controller -n <namespace>
   ```

**Solutions:**

```bash
# Terminate stuck sync
argocd app terminate-op <app-name>

# Force sync with replace
argocd app sync <app-name> --force

# Sync with prune
argocd app sync <app-name> --prune

# Skip hooks if needed
argocd app sync <app-name> --sync-option SkipHooks=true
```

### Issue 3: Application Not Auto-Syncing

**Symptoms:**
- Git commits not triggering syncs
- Manual sync works but auto-sync doesn't
- Delay in detecting changes

**Investigation:**

```bash
# Check sync policy
argocd app get <app-name> | grep -A 5 "Sync Policy"

# Check repo connection
argocd repo list

# Check if repo is reachable
argocd repo get <repo-url>

# Check ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

**Common Causes:**

1. **Auto-sync not enabled**
   ```bash
   # Check current setting
   argocd app get <app-name> --show-params | grep "Auto Sync"
   ```

2. **Sync windows**: Only sync during specific times
   ```bash
   # Check sync windows
   argocd app get <app-name> | grep -A 5 "Sync Window"
   ```

3. **Self-heal disabled**: Auto-sync on but not healing drift
   ```bash
   argocd app get <app-name> | grep "Self Heal"
   ```

4. **Git webhook not configured**: ArgoCD polling instead of webhook
   ```bash
   # Check webhook in Git provider (GitHub/GitLab)
   # Should point to: https://<argocd-server>/api/webhook
   ```

**Solutions:**

```bash
# Enable auto-sync
argocd app set <app-name> --sync-policy automated

# Enable self-heal
argocd app set <app-name> --self-heal

# Enable auto-prune
argocd app set <app-name> --auto-prune

# Force immediate check
argocd app get <app-name> --refresh

# Hard refresh (bypass cache)
argocd app get <app-name> --hard-refresh
```

### Issue 4: Application Health Unknown or Degraded

**Symptoms:**
- Health shows "Unknown" or "Degraded"
- Resources appear healthy in cluster
- Can't determine what's wrong

**Investigation:**

```bash
# Get detailed health info
argocd app get <app-name> --show-operation

# Check resource tree
argocd app resources <app-name>

# Check individual resource health
argocd app get <app-name> --show-params

# Check custom health checks
argocd app get <app-name> | grep -A 10 "Health"
```

**Common Causes:**

1. **Custom resource without health check**: ArgoCD doesn't know how to assess health
   ```bash
   # Check for CRDs
   kubectl get crd

   # See which resources ArgoCD is tracking
   argocd app get <app-name> --show-params
   ```

2. **Readiness probe failing**: Pods running but not ready
   ```bash
   kubectl get pods -n <namespace>
   kubectl describe pod/<pod-name> -n <namespace> | grep -A 5 "Readiness"
   ```

3. **Job not completing**: Job resource shows as progressing
   ```bash
   kubectl get jobs -n <namespace>
   kubectl describe job/<job-name> -n <namespace>
   ```

**Solutions:**

```bash
# For custom resources, add health check to ArgoCD configmap
kubectl edit configmap argocd-cm -n argocd
# Add:
data:
  resource.customizations.health.<group>_<kind>: |
    hs = {}
    hs.status = "Healthy"
    hs.message = "Resource is healthy"
    return hs

# Ignore health of specific resources
# In application spec:
spec:
  ignoreDifferences:
  - group: batch
    kind: Job
    jqPathExpressions:
    - .status

# Exclude resource from health check
spec:
  syncPolicy:
    syncOptions:
    - Validate=false  # Skip validation
```

### Issue 5: Sync Waves Not Working

**Symptoms:**
- Resources deploying in wrong order
- Dependencies not met during deployment
- Some resources fail due to timing

**Investigation:**

```bash
# Check for sync wave annotations
cd <gitops-repo>
grep -r "argocd.argoproj.io/sync-wave" .

# View sync phases
argocd app get <app-name> --show-operation | grep -A 20 "Sync Result"

# Check sync order
argocd app manifests <app-name> | grep -B 5 "sync-wave"
```

**Common Causes:**

1. **Missing sync wave annotations**: Not all resources annotated
2. **Incorrect wave numbers**: Waves in wrong order
3. **Hooks interfering**: Pre/post sync hooks conflicting

**Solutions:**

```yaml
# Add sync waves to manifests (lower numbers deploy first)
# Database first (wave 0)
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-config
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Application second (wave 1)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  annotations:
    argocd.argoproj.io/sync-wave: "1"

# Ingress last (wave 2)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

### Issue 6: Application Not Appearing in ArgoCD UI

**Symptoms:**
- Application manifest in Git but not in ArgoCD
- ArgoCD CLI shows app but UI doesn't
- App deleted but Git still has it

**Investigation:**

```bash
# List all applications
argocd app list

# Check if app exists
argocd app get <app-name>

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Check application manifest
kubectl get application <app-name> -n argocd -o yaml
```

**Common Causes:**

1. **App-of-apps pattern**: Parent app hasn't synced
2. **Wrong namespace**: Application created in wrong namespace
3. **RBAC restrictions**: User doesn't have permission to view

**Solutions:**

```bash
# Check if using app-of-apps
argocd app get <parent-app-name>

# Create application manually
argocd app create <app-name> \
  --repo <repo-url> \
  --path <path> \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace <namespace>

# Or apply Application CRD directly
kubectl apply -f application.yaml -n argocd
```

## ArgoCD Sync Options

Useful sync options for different scenarios:

```bash
# Sync with prune (delete resources not in Git)
argocd app sync <app-name> --prune

# Sync with force (replace resources)
argocd app sync <app-name> --force

# Dry run (preview changes)
argocd app sync <app-name> --dry-run

# Sync specific resources only
argocd app sync <app-name> --resource apps:Deployment:my-deployment

# Skip schema validation
argocd app sync <app-name> --validate=false

# Skip hooks
argocd app sync <app-name> --sync-option SkipHooks=true

# Apply out of sync only
argocd app sync <app-name> --apply-out-of-sync-only=true

# Replace resources
argocd app sync <app-name> --replace

# Server-side apply
argocd app sync <app-name> --server-side
```

## ArgoCD Application Manifest Best Practices

### Basic Application Template

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  # Finalizer ensures cleanup
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/org/repo
    targetRevision: main
    path: apps/my-app

    # For Helm charts
    # helm:
    #   valueFiles:
    #   - values-prod.yaml

    # For Kustomize
    # kustomize:
    #   version: v4.5.7

  destination:
    server: https://kubernetes.default.svc
    namespace: my-namespace

  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Sync when cluster state drifts
      allowEmpty: false

    syncOptions:
    - CreateNamespace=true
    - PruneLast=true

    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  # Ignore differences for known sources
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas  # Ignore HPA changes
```

### Health Check Customization

For custom resources:

```yaml
# Add to argocd-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.health.argoproj.io_Rollout: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase ~= nil then
        if obj.status.phase == "Healthy" then
          hs.status = "Healthy"
          hs.message = obj.status.message
          return hs
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for rollout"
    return hs
```

## Troubleshooting Commands Reference

Quick command reference:

```bash
# Application status
argocd app list
argocd app get <app-name>
argocd app history <app-name>
argocd app logs <app-name>

# Sync operations
argocd app sync <app-name>
argocd app sync <app-name> --dry-run
argocd app terminate-op <app-name>

# Refresh
argocd app get <app-name> --refresh
argocd app get <app-name> --hard-refresh

# Diff and manifests
argocd app diff <app-name>
argocd app manifests <app-name>

# Configuration
argocd app set <app-name> --sync-policy automated
argocd app set <app-name> --self-heal
argocd app unset <app-name> --sync-policy

# Rollback
argocd app rollback <app-name> <history-id>

# Resources
argocd app resources <app-name>
argocd app delete-resource <app-name> --resource-name=<name>

# Debugging
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## Common Error Messages

### "ComparisonError: Failed to load target state"

**Cause**: ArgoCD can't parse manifests from Git

**Solution**:
```bash
# Validate manifests locally
kubectl apply --dry-run=client -f <manifest>

# Check ArgoCD can generate manifests
argocd app manifests <app-name>
```

### "PermissionDenied: ... is forbidden"

**Cause**: ArgoCD service account lacks permissions

**Solution**:
```bash
# Check permissions
kubectl auth can-i create deployments \
  --as=system:serviceaccount:argocd:argocd-application-controller \
  -n <namespace>

# Grant permissions (if appropriate)
kubectl create rolebinding argocd-admin \
  --clusterrole=admin \
  --serviceaccount=argocd:argocd-application-controller \
  -n <namespace>
```

### "ResourceNotFound: the server could not find the requested resource"

**Cause**: CRD not installed or API version doesn't exist

**Solution**:
```bash
# Check if CRD exists
kubectl get crd | grep <resource-kind>

# Check API versions available
kubectl api-resources | grep <resource-kind>

# Install required CRD or update API version in manifest
```

## Emergency Recovery

### ArgoCD Not Responding

```bash
# Restart ArgoCD components
kubectl rollout restart deployment/argocd-application-controller -n argocd
kubectl rollout restart deployment/argocd-repo-server -n argocd
kubectl rollout restart deployment/argocd-server -n argocd

# Check component status
kubectl get pods -n argocd

# Check logs for errors
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

### Bypass ArgoCD (Emergency)

```bash
# Temporarily disable ArgoCD management
kubectl annotate application <app-name> -n argocd \
  argocd.argoproj.io/compare-options=IgnoreExtraneous

# Apply directly with kubectl
kubectl apply -f fixed-manifest.yaml

# Update Git to match
# Then remove annotation:
kubectl annotate application <app-name> -n argocd \
  argocd.argoproj.io/compare-options-
```

### Full Application Reset

```bash
# Delete application (keeps resources)
argocd app delete <app-name> --cascade=false

# Recreate application
argocd app create <app-name> --repo <repo> --path <path> --dest-namespace <ns>

# Sync
argocd app sync <app-name>
```
