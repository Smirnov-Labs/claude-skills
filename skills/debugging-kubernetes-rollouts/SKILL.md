---
name: debugging-kubernetes-rollouts
description: Use this skill when debugging Kubernetes deployments, troubleshooting failed rollouts, investigating ArgoCD sync issues, fixing GitOps deployment problems, analyzing pod failures, resolving image pull errors, or diagnosing service connectivity issues. This includes working with kubectl, ArgoCD CLI, GitOps repositories, and the kubernetes MCP server to systematically investigate and fix deployment issues.
---

# Kubernetes Rollout Debugging Expert

Systematically debug Kubernetes deployments using kubectl, ArgoCD, GitOps workflows, and the kubernetes MCP server.

## Core Philosophy: GitOps-First Debugging

When debugging K8s rollouts in a GitOps environment:
1. **Understand the flow**: Git → ArgoCD → Kubernetes cluster
2. **Check each layer**: Git manifest → ArgoCD sync status → K8s resources → Running pods
3. **Use the right tool**: MCP for queries, kubectl for inspection, git for history
4. **Fix in Git**: Manual kubectl changes are temporary; GitOps will revert them

## Tool Selection Strategy

### Use Kubernetes MCP Server When:
- Querying resource status across namespaces
- Getting structured data about deployments
- Listing resources with filtering
- Reading pod logs systematically
- Checking resource health

### Use kubectl CLI When:
- Detailed resource inspection (`kubectl describe`)
- Executing commands in pods (`kubectl exec`)
- Port forwarding for debugging
- Applying temporary test manifests
- Getting raw YAML/JSON output

### Use ArgoCD CLI When:
- Checking application sync status
- Forcing syncs or refreshes
- Viewing sync history
- Debugging sync errors
- Managing application health

### Use Git When:
- Reviewing manifest changes
- Comparing versions
- Checking commit history
- Understanding deployment progression

## Systematic Debugging Workflow

### Phase 1: Deployment Status Assessment

Start by understanding the current state:

#### Check ArgoCD Application Status

```bash
# List all applications
argocd app list

# Get specific application status
argocd app get <app-name>

# Check sync status
argocd app get <app-name> --show-operation

# View recent sync history
argocd app history <app-name>
```

#### Check Kubernetes Deployment Status

```bash
# Get deployment status
kubectl get deployments -n <namespace>

# Check rollout status
kubectl rollout status deployment/<name> -n <namespace>

# View rollout history
kubectl rollout history deployment/<name> -n <namespace>

# Get detailed deployment info
kubectl describe deployment/<name> -n <namespace>
```

#### Check Pod Status

```bash
# List all pods in namespace
kubectl get pods -n <namespace>

# Watch pod status in real-time
kubectl get pods -n <namespace> -w

# Get pods with more details
kubectl get pods -n <namespace> -o wide

# Check specific pod
kubectl describe pod/<pod-name> -n <namespace>
```

### Phase 2: Common Failure Scenarios

#### Scenario 1: ArgoCD Out of Sync

**Symptoms:**
- ArgoCD shows "OutOfSync" status
- Manifests in Git don't match cluster state
- Application health is "Degraded"

**Investigation:**

```bash
# Check what's out of sync
argocd app diff <app-name>

# Check if auto-sync is enabled
argocd app get <app-name> | grep -A 5 "Sync Policy"

# View sync operation status
argocd app get <app-name> --show-operation
```

**Common Causes:**
1. **Manual kubectl changes**: Someone modified resources directly
2. **Sync disabled**: Auto-sync turned off
3. **Sync failed**: Error during last sync attempt
4. **Resource hooks**: Pre/post-sync hooks failed

**Solutions:**

```bash
# Force sync
argocd app sync <app-name>

# Sync with prune (delete extra resources)
argocd app sync <app-name> --prune

# Hard refresh (force ArgoCD to re-fetch git)
argocd app get <app-name> --hard-refresh

# If manual changes need to be kept, update Git first:
kubectl get deployment/<name> -n <namespace> -o yaml > current-state.yaml
# Then update your Git repo with desired state
```

#### Scenario 2: Image Pull Errors

**Symptoms:**
- Pods stuck in `ImagePullBackOff` or `ErrImagePull`
- Deployment rollout stuck

**Investigation:**

```bash
# Check pod events
kubectl describe pod/<pod-name> -n <namespace> | grep -A 10 "Events:"

# Check image pull secrets
kubectl get secrets -n <namespace> | grep docker

# Verify image exists
kubectl get pod/<pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].image}'
```

**Common Causes:**
1. **Image doesn't exist**: Wrong tag or repository
2. **Authentication failed**: Missing or incorrect image pull secret
3. **Rate limiting**: Docker Hub rate limits hit
4. **Network issues**: Can't reach registry

**Solutions:**

```bash
# Check if image pull secret exists
kubectl get secret <secret-name> -n <namespace> -o yaml

# Test image pull manually (if you have access)
docker pull <image:tag>

# Check recent tags in GitOps repo
cd <gitops-repo>
git log --oneline -10 -- path/to/deployment.yaml | grep image

# Fix in Git:
# 1. Update image tag to known good version
# 2. Verify image pull secret is configured
# 3. Commit and push
# 4. Wait for ArgoCD sync or force: argocd app sync <app-name>
```

#### Scenario 3: CrashLoopBackOff

**Symptoms:**
- Pods restarting repeatedly
- Application never becomes healthy
- High restart count

**Investigation:**

```bash
# Check pod status
kubectl get pods -n <namespace>

# Get logs from current container
kubectl logs <pod-name> -n <namespace>

# Get logs from previous container (after crash)
kubectl logs <pod-name> -n <namespace> --previous

# Check all containers in pod
kubectl logs <pod-name> -n <namespace> --all-containers=true

# Follow logs in real-time
kubectl logs <pod-name> -n <namespace> -f

# Check pod events
kubectl describe pod/<pod-name> -n <namespace>
```

**Common Causes:**
1. **Application error**: Code bug causing crash
2. **Configuration error**: Missing env vars or config
3. **Health check failure**: Liveness probe failing
4. **Resource limits**: OOM killed
5. **Dependency unavailable**: Can't connect to database/service

**Solutions:**

```bash
# Check container exit code
kubectl get pod/<pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'

# Check for OOM kills
kubectl describe pod/<pod-name> -n <namespace> | grep -i "oom"

# Inspect environment variables
kubectl get pod/<pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].env[*]}'

# Check resource limits
kubectl get pod/<pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].resources}'

# Exec into running container (if possible)
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Check liveness/readiness probes
kubectl get deployment/<name> -n <namespace> -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'
```

**Fix in GitOps:**
1. Update configuration in Git (env vars, resource limits, probes)
2. Commit and push
3. Sync via ArgoCD
4. Monitor: `kubectl get pods -n <namespace> -w`

#### Scenario 4: Service Not Reachable

**Symptoms:**
- Pods running but service unreachable
- Ingress/LoadBalancer not working
- Internal service discovery failing

**Investigation:**

```bash
# Check service
kubectl get svc -n <namespace>
kubectl describe svc/<service-name> -n <namespace>

# Check endpoints (should match pod IPs)
kubectl get endpoints <service-name> -n <namespace>

# Check ingress
kubectl get ingress -n <namespace>
kubectl describe ingress/<ingress-name> -n <namespace>

# Test service from within cluster
kubectl run test-pod --rm -it --image=busybox -n <namespace> -- sh
# Then: wget -O- http://<service-name>:<port>

# Check network policies
kubectl get networkpolicies -n <namespace>
```

**Common Causes:**
1. **Selector mismatch**: Service selector doesn't match pod labels
2. **Wrong port**: Service port doesn't match container port
3. **No healthy pods**: All pods failing health checks
4. **Network policy**: Traffic blocked by policy
5. **Ingress misconfiguration**: Wrong host/path rules

**Solutions:**

```bash
# Verify service selector matches pod labels
kubectl get svc/<service-name> -n <namespace> -o jsonpath='{.spec.selector}'
kubectl get pods -n <namespace> --show-labels

# Check service targets actual pods
kubectl get endpoints <service-name> -n <namespace>
# Should show pod IPs - if empty, selector is wrong

# Test port connectivity
kubectl port-forward pod/<pod-name> -n <namespace> 8080:8080
# Then curl localhost:8080

# Check if ingress controller is running
kubectl get pods -n ingress-nginx  # or your ingress namespace
```

#### Scenario 5: Deployment Stuck (Rollout Paused)

**Symptoms:**
- New pods not being created
- Old pods still running
- Deployment shows partial rollout

**Investigation:**

```bash
# Check rollout status
kubectl rollout status deployment/<name> -n <namespace>

# Check deployment conditions
kubectl get deployment/<name> -n <namespace> -o jsonpath='{.status.conditions[*]}'

# Check replica counts
kubectl get deployment/<name> -n <namespace> -o jsonpath='{.status}'

# Check replicaset status
kubectl get rs -n <namespace>
kubectl describe rs/<replicaset-name> -n <namespace>
```

**Common Causes:**
1. **Insufficient resources**: Cluster can't schedule new pods
2. **Pod disruption budget**: PDB preventing pod eviction
3. **Node selector/affinity**: No nodes match requirements
4. **Quota exceeded**: Namespace resource quota reached

**Solutions:**

```bash
# Check node resources
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check pod pending reasons
kubectl describe pod/<pending-pod> -n <namespace>

# Check resource quotas
kubectl get resourcequota -n <namespace>
kubectl describe resourcequota -n <namespace>

# Check pod disruption budgets
kubectl get pdb -n <namespace>

# Force rollout restart
kubectl rollout restart deployment/<name> -n <namespace>

# Rollback if needed
kubectl rollout undo deployment/<name> -n <namespace>
```

### Phase 3: GitOps-Specific Debugging

#### Check Git Repository State

```bash
cd <gitops-repo>

# Check recent changes to deployment
git log --oneline -10 -- path/to/deployment.yaml

# Compare with previous version
git diff HEAD~1 HEAD -- path/to/deployment.yaml

# Show specific commit changes
git show <commit-hash>:path/to/deployment.yaml

# Check all changes to namespace
git log --oneline -- namespace/<namespace>/
```

#### Verify Manifest Syntax

```bash
# Validate YAML syntax
kubectl apply --dry-run=client -f deployment.yaml

# Validate with server-side dry run
kubectl apply --dry-run=server -f deployment.yaml

# Use kubeval for additional validation
kubeval deployment.yaml

# Check with kustomize if using overlays
kustomize build overlays/production | kubectl apply --dry-run=client -f -
```

#### ArgoCD Sync Waves and Hooks

```bash
# Check for sync waves/hooks in manifests
grep -r "argocd.argoproj.io/sync-wave" .
grep -r "argocd.argoproj.io/hook" .

# View sync operation details
argocd app get <app-name> --show-operation

# Check resource hooks
argocd app get <app-name> | grep -A 5 "Resource Hooks"
```

### Phase 4: Progressive Debugging

When systematic checks don't reveal the issue:

#### 1. Isolate the Problem

```bash
# Deploy minimal test version
# Create test-pod.yaml with known good image
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: <namespace>
spec:
  containers:
  - name: test
    image: nginx:latest
    ports:
    - containerPort: 80
EOF

# Wait and check
kubectl get pod test-pod -n <namespace>

# If this works, issue is with your application
# If this fails, issue is with cluster/namespace
```

#### 2. Compare Working vs Broken

```bash
# If you have working environment (e.g., staging):
kubectl get deployment/<name> -n <namespace> -o yaml --context=staging > staging.yaml
kubectl get deployment/<name> -n <namespace> -o yaml --context=production > production.yaml

# Diff the outputs
diff staging.yaml production.yaml

# Check for configuration differences
diff <(kubectl get configmap -n <namespace> --context=staging -o yaml) \
     <(kubectl get configmap -n <namespace> --context=production -o yaml)
```

#### 3. Check Cluster-Level Issues

```bash
# Check cluster health
kubectl get nodes
kubectl top nodes

# Check cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Check cluster-wide issues
kubectl get pods --all-namespaces | grep -v "Running\|Completed"

# Check system pods
kubectl get pods -n kube-system
```

## Using Kubernetes MCP Server

The kubernetes MCP server provides structured data access. Here's when and how to use it:

### Getting Deployment Status

The MCP server can query deployments systematically:

```
Use kubernetes MCP to list all deployments in namespace <namespace>
Use kubernetes MCP to get deployment <name> details
Use kubernetes MCP to check pod status for deployment <name>
```

### Reading Pod Logs

```
Use kubernetes MCP to get logs from pod <pod-name>
Use kubernetes MCP to get logs from previous container in pod <pod-name>
```

### Resource Queries

```
Use kubernetes MCP to list all services in namespace
Use kubernetes MCP to get ingress configuration
Use kubernetes MCP to check configmap contents
```

**Note**: MCP is great for querying and reading. For exec, port-forward, and interactive debugging, use kubectl CLI.

## Debugging Decision Tree

```
Deployment failing?
├─ ArgoCD shows OutOfSync?
│  ├─ Check: argocd app get <app-name>
│  ├─ Run: argocd app diff <app-name>
│  └─ Fix: Sync or update Git
│
├─ Pods not starting?
│  ├─ Check: kubectl get pods -n <namespace>
│  │
│  ├─ ImagePullBackOff?
│  │  ├─ Verify image exists
│  │  ├─ Check image pull secret
│  │  └─ Review recent Git changes to image tag
│  │
│  ├─ Pending?
│  │  ├─ Check: kubectl describe pod
│  │  ├─ Insufficient resources?
│  │  └─ Node selector not matching?
│  │
│  └─ CrashLoopBackOff?
│     ├─ Check logs: kubectl logs --previous
│     ├─ Check events: kubectl describe pod
│     └─ Check for OOM, config errors, health check failures
│
├─ Pods running but service unreachable?
│  ├─ Check service selector matches pod labels
│  ├─ Check endpoints exist
│  ├─ Test connectivity with port-forward
│  └─ Check ingress configuration
│
└─ Rollout stuck?
   ├─ Check rollout status
   ├─ Check resource quotas
   ├─ Check pod disruption budgets
   └─ Consider rollback
```

## Emergency Procedures

### Immediate Rollback

```bash
# Rollback deployment
kubectl rollout undo deployment/<name> -n <namespace>

# Rollback to specific revision
kubectl rollout undo deployment/<name> -n <namespace> --to-revision=<number>

# In GitOps, revert Git commit
cd <gitops-repo>
git revert <bad-commit-hash>
git push
argocd app sync <app-name>
```

### Force Pod Restart

```bash
# Delete pods (deployment will recreate)
kubectl delete pod -l app=<app-label> -n <namespace>

# Or rollout restart
kubectl rollout restart deployment/<name> -n <namespace>
```

### Disable ArgoCD Auto-Sync

```bash
# Temporarily disable auto-sync for manual fixes
argocd app set <app-name> --sync-policy none

# Re-enable after fixing
argocd app set <app-name> --sync-policy automated
```

### Scale to Zero (Emergency Stop)

```bash
# In Git, set replicas: 0
# Or temporarily:
kubectl scale deployment/<name> --replicas=0 -n <namespace>

# Remember: GitOps will revert this!
```

## Best Practices

### 1. Always Check Git First

Before debugging in cluster, check Git history:
```bash
cd <gitops-repo>
git log --oneline -20 -- path/to/app/
```

Recent changes are the most likely culprit.

### 2. Use Namespaces for Isolation

```bash
# Set default namespace
kubectl config set-context --current --namespace=<namespace>

# Or use -n flag consistently
alias k='kubectl -n <namespace>'
```

### 3. Tag Your Debugging

When testing fixes, use descriptive Git commit messages:
```bash
git commit -m "fix: increase memory limit for api deployment (OOMKilled)"
```

### 4. Document in ArgoCD

Use ArgoCD annotations for context:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/tracking-id: "deployment:<namespace>/api"
    notes: "Increased memory due to OOM 2025-11-02"
```

### 5. Set Up Alerts

Monitor for common issues:
- Pods restarting frequently
- Image pull failures
- ArgoCD sync failures
- Resource exhaustion

## Troubleshooting Checklist

Quick reference for systematic debugging:

- [ ] Check ArgoCD app status: `argocd app get <app-name>`
- [ ] Check deployment status: `kubectl get deployment -n <namespace>`
- [ ] Check pod status: `kubectl get pods -n <namespace>`
- [ ] Check pod logs: `kubectl logs <pod-name> -n <namespace>`
- [ ] Check pod events: `kubectl describe pod/<pod-name> -n <namespace>`
- [ ] Check service endpoints: `kubectl get endpoints -n <namespace>`
- [ ] Check recent Git changes: `git log -10 -- path/to/deployment.yaml`
- [ ] Verify manifest syntax: `kubectl apply --dry-run=client -f deployment.yaml`
- [ ] Check node resources: `kubectl top nodes`
- [ ] Check namespace quotas: `kubectl get resourcequota -n <namespace>`
- [ ] Check for manual changes: `argocd app diff <app-name>`

## Additional Resources

See supporting files:
- `./argocd-troubleshooting.md` - Detailed ArgoCD debugging
- `./gitops-workflows.md` - GitOps best practices and patterns
- `./test-scripts/` - Diagnostic scripts for K8s debugging
