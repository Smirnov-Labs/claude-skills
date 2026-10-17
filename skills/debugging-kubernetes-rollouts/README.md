# Kubernetes Rollout Debugging Skill

Comprehensive debugging skill for Kubernetes deployments with ArgoCD and GitOps workflows.

## When This Skill Activates

This skill automatically activates when you mention:
- Kubernetes deployments failing
- ArgoCD sync issues
- GitOps deployment problems
- Pod failures
- Image pull errors
- Service connectivity issues
- Rollout stuck or hanging
- kubectl, ArgoCD, or kubernetes MCP

## What This Skill Provides

### 1. Systematic Debugging Workflow

Phase-by-phase approach covering:
- Deployment status assessment (ArgoCD + Kubernetes)
- Common failure scenarios with solutions
- GitOps-specific debugging
- Progressive debugging techniques

### 2. Tool Selection Strategy

Guidance on when to use:
- **Kubernetes MCP Server**: Structured queries, pod logs, resource listing
- **kubectl CLI**: Detailed inspection, exec, port-forward
- **ArgoCD CLI**: Application sync status, force syncs, history
- **Git**: Manifest history, comparing versions, rollbacks

### 3. Comprehensive Troubleshooting Guides

**ArgoCD Troubleshooting** (`./argocd-troubleshooting.md`):
- OutOfSync applications
- Sync operation failures
- Auto-sync not working
- Health status issues
- Sync waves debugging
- Emergency recovery procedures

**GitOps Workflows** (`./gitops-workflows.md`):
- Repository structures (monorepo, per-env, per-team)
- Kustomize patterns (base + overlays)
- ArgoCD Application patterns (app-of-apps, ApplicationSet)
- Deployment strategies (blue-green, canary)
- Promotion workflows
- Best practices

### 4. Diagnostic Scripts

Ready-to-use bash scripts:

```bash
# Diagnose Kubernetes deployment
./test-scripts/diagnose-deployment.sh -d api -n production

# Check ArgoCD application health
./test-scripts/check-argocd-app.sh -a api-production
```

## Quick Start

### Option 1: Let Claude Use the Skill

Just describe your issue:

```
My Kubernetes deployment is stuck. ArgoCD shows OutOfSync.
```

Claude will:
1. Check ArgoCD application status
2. Inspect Kubernetes deployment
3. Analyze pod failures
4. Provide systematic solutions

### Option 2: Explicitly Invoke

```
debugging-kubernetes-rollouts

My pods are in ImagePullBackOff state
```

### Option 3: Use Diagnostic Scripts

```bash
cd ~/.claude/skills/debugging-kubernetes-rollouts

# Check deployment
./test-scripts/diagnose-deployment.sh -d my-app -n production

# Check ArgoCD app
./test-scripts/check-argocd-app.sh -a my-app-production
```

## File Structure

```
debugging-kubernetes-rollouts/
├── SKILL.md                          # Main debugging workflow
├── README.md                         # This file
├── argocd-troubleshooting.md         # ArgoCD-specific issues
├── gitops-workflows.md               # GitOps best practices
├── test-scripts/
│   ├── diagnose-deployment.sh        # K8s deployment diagnostics
│   └── check-argocd-app.sh           # ArgoCD app health check
└── examples/
    └── (example manifests and patterns)
```

## Common Scenarios

### Scenario: "My ArgoCD app is OutOfSync"

**Claude will:**
1. Check what's different: `argocd app diff <app-name>`
2. Identify cause (manual changes, sync failed, hooks)
3. Provide solution (sync, update Git, ignore differences)

**You can also:**
```bash
./test-scripts/check-argocd-app.sh -a my-app
```

### Scenario: "Pods stuck in ImagePullBackOff"

**Claude will:**
1. Check image tag in manifest
2. Verify image pull secrets exist
3. Review recent Git changes
4. Suggest fixes (correct tag, add secret)

**Manual check:**
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Events:"
```

### Scenario: "Deployment rollout stuck"

**Claude will:**
1. Check rollout status
2. Look for pending pods
3. Check resource quotas
4. Identify blockers (resources, PDB, node selectors)
5. Suggest solutions (scale resources, adjust PDB)

**Quick diagnosis:**
```bash
./test-scripts/diagnose-deployment.sh -d my-app -n production
```

### Scenario: "Service not reachable after deployment"

**Claude will:**
1. Verify service selector matches pod labels
2. Check endpoints exist
3. Test connectivity with port-forward
4. Verify ingress configuration
5. Check network policies

### Scenario: "CrashLoopBackOff"

**Claude will:**
1. Get logs from crashed container
2. Check for OOM kills
3. Inspect environment variables
4. Review resource limits
5. Check dependencies (database, etc.)

## Integration with Tools

### Using Kubernetes MCP

The skill leverages the kubernetes MCP server for queries:

```
Use kubernetes MCP to list deployments in production namespace
Use kubernetes MCP to get pod logs from api-pod
Use kubernetes MCP to check service endpoints
```

**When to use MCP:**
- Querying resource status
- Reading pod logs
- Listing resources with filters
- Getting structured data

**When to use kubectl:**
- Interactive debugging (exec, port-forward)
- Detailed resource inspection (describe)
- Real-time watching (kubectl get -w)
- Applying test manifests

### Using ArgoCD CLI

```bash
# Install if needed
brew install argocd  # macOS
# or
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

# Login
argocd login <argocd-server> --username admin

# Common commands (automatically used by Claude)
argocd app list
argocd app get <app-name>
argocd app sync <app-name>
argocd app diff <app-name>
```

### Using kubectl

```bash
# The skill uses kubectl extensively
kubectl get deployments -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl rollout status deployment/<name> -n <namespace>
```

## Key Features

### GitOps-First Debugging

Follows the flow: **Git → ArgoCD → Kubernetes cluster**

Always checks:
1. Git history (what changed?)
2. ArgoCD sync status (is it synced?)
3. Kubernetes resources (are they healthy?)

### Escape Local Minimums

Prevents debugging loops with:
- Systematic checklists
- Progressive debugging
- Component isolation
- Comparison with working environments

### Decision Trees

Quick diagnosis paths for:
- ArgoCD OutOfSync
- ImagePullBackOff
- CrashLoopBackOff
- Service unreachable
- Rollout stuck

### Emergency Procedures

Fast recovery options:
- Immediate rollback (Git revert + ArgoCD sync)
- Force pod restart
- Disable auto-sync temporarily
- Scale to zero (emergency stop)

## Debugging Workflow

### Phase 1: Assessment

```bash
# ArgoCD status
argocd app get <app-name>

# Kubernetes status
kubectl get deployment <name> -n <namespace>
kubectl get pods -n <namespace>
```

### Phase 2: Investigation

```bash
# Check what's wrong
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# Check ArgoCD differences
argocd app diff <app-name>

# Check Git history
cd <gitops-repo>
git log --oneline -10 -- path/to/app/
```

### Phase 3: Fix in Git

```bash
# Update manifests
cd <gitops-repo>
vim apps/my-app/deployment.yaml

# Commit and push
git commit -am "fix: increase memory limit"
git push

# Sync in ArgoCD
argocd app sync <app-name>
```

### Phase 4: Verify

```bash
# Watch pods
kubectl get pods -n <namespace> -w

# Check deployment health
kubectl rollout status deployment/<name> -n <namespace>

# Verify service
curl http://<service-endpoint>/health
```

## Best Practices

### 1. Always Check Git First

Recent commits are the most likely cause:

```bash
cd <gitops-repo>
git log --oneline -20 -- apps/my-app/
```

### 2. Fix in Git, Not kubectl

Manual kubectl changes are temporary - ArgoCD will revert them.

**Bad:**
```bash
kubectl set image deployment/api api=myapp:v1.2.0  # Temporary!
```

**Good:**
```bash
cd <gitops-repo>
cd apps/api/overlays/production
kustomize edit set image myapp=myapp:v1.2.0
git commit -am "Update to v1.2.0"
git push
argocd app sync api-production
```

### 3. Use Sync Waves for Dependencies

```yaml
# Database first (wave 0)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Application second (wave 1)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

### 4. Validate Before Pushing

```bash
# Validate manifests locally
kustomize build overlays/production | kubectl apply --dry-run=client -f -

# Server-side validation
kustomize build overlays/production | kubectl apply --dry-run=server -f -
```

### 5. Monitor Deployments

After pushing changes:

```bash
# Watch ArgoCD sync
argocd app wait <app-name> --health --timeout 300

# Watch pods
kubectl get pods -n <namespace> -w

# Check logs
kubectl logs -f deployment/<name> -n <namespace>
```

## Troubleshooting the Skill

### Skill not activating?

Keywords that trigger it:
- "kubernetes deployment"
- "argocd sync"
- "gitops"
- "pod failing"
- "rollout stuck"

Try being explicit: "Help me debug this Kubernetes deployment"

### Need ArgoCD CLI?

```bash
# Install
brew install argocd  # macOS
# or download from releases

# Login
argocd login <server> --username admin
```

### Scripts not working?

Make sure they're executable:

```bash
chmod +x ~/.claude/skills/debugging-kubernetes-rollouts/test-scripts/*.sh
```

Verify tools are installed:

```bash
kubectl version --client
argocd version --client  # Optional but recommended
```

## Advanced Usage

### Multi-Cluster Debugging

```bash
# List contexts
kubectl config get-contexts

# Check deployment across clusters
for ctx in staging production; do
  echo "=== $ctx ==="
  kubectl get deployment api -n production --context=$ctx
done
```

### Comparing Environments

```bash
# Compare staging vs production
diff <(kubectl get deployment api -n api-staging -o yaml) \
     <(kubectl get deployment api -n api-prod -o yaml)
```

### GitOps Promotion

```bash
# Promote dev → staging
cd gitops-repo/apps/api
TAG=$(yq e '.images[0].newTag' overlays/dev/kustomization.yaml)
cd overlays/staging
kustomize edit set image myapp=myapp:$TAG
git commit -am "Promote $TAG to staging"
git push
```

## Resources

### Official Documentation

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)

### Quick Reference

**kubectl Cheat Sheet:**
- https://kubernetes.io/docs/reference/kubectl/cheatsheet/

**ArgoCD CLI Reference:**
- https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd/

**Kustomize Examples:**
- https://github.com/kubernetes-sigs/kustomize/tree/master/examples

## Support

For issues with the skill itself:
- Check `SKILL.md` for the full workflow
- Review `argocd-troubleshooting.md` for ArgoCD-specific help
- Check `gitops-workflows.md` for best practices
- Run diagnostic scripts in `test-scripts/`

## Updates

This skill is designed to be:
- **Tool-agnostic**: Works with kubectl, ArgoCD CLI, and kubernetes MCP
- **Version-flexible**: Works with Kubernetes 1.20+
- **Extensible**: Add your own patterns and scripts

To customize:
1. Edit supporting files for your environment
2. Add scripts in `test-scripts/`
3. Document your patterns in `examples/`
