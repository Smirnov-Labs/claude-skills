#!/usr/bin/env bash
#
# ArgoCD Application Health Check Script
#
# Checks ArgoCD application status and common issues
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Usage
usage() {
  echo "Usage: $0 -a APP_NAME"
  echo ""
  echo "Options:"
  echo "  -a APP_NAME    ArgoCD application name"
  echo ""
  echo "Example:"
  echo "  $0 -a api-production"
  exit 1
}

# Parse arguments
while getopts "a:h" opt; do
  case $opt in
    a) APP_NAME="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [ -z "$APP_NAME" ]; then
  usage
fi

echo "========================================="
echo "ArgoCD Application Diagnostics"
echo "========================================="
echo "Application: $APP_NAME"
echo ""

# Check if argocd CLI is available
if ! command -v argocd &> /dev/null; then
  echo -e "${YELLOW}⚠ argocd CLI not found${NC}"
  echo "Install with: brew install argocd"
  echo ""
  echo "Checking with kubectl instead..."

  # Fallback to kubectl
  if kubectl get application "$APP_NAME" -n argocd &> /dev/null; then
    echo -e "${GREEN}✓ Application exists${NC}"
    kubectl get application "$APP_NAME" -n argocd -o yaml
  else
    echo -e "${RED}✗ Application not found${NC}"
    exit 1
  fi
  exit 0
fi

# Check if app exists
if ! argocd app get "$APP_NAME" &> /dev/null; then
  echo -e "${RED}✗ Application '$APP_NAME' not found${NC}"
  echo ""
  echo "Available applications:"
  argocd app list
  exit 1
fi

echo -e "${GREEN}✓ Application exists${NC}"
echo ""

# 1. Application Status
echo "========================================="
echo "1. Application Status"
echo "========================================="
argocd app get "$APP_NAME"
echo ""

# 2. Sync Status
echo "========================================="
echo "2. Sync Status"
echo "========================================="
SYNC_STATUS=$(argocd app get "$APP_NAME" -o json | jq -r '.status.sync.status')
echo "Sync Status: $SYNC_STATUS"

if [ "$SYNC_STATUS" = "Synced" ]; then
  echo -e "${GREEN}✓ Application is synced${NC}"
else
  echo -e "${YELLOW}⚠ Application is out of sync${NC}"
  echo ""
  echo "Checking differences..."
  argocd app diff "$APP_NAME" || true
fi
echo ""

# 3. Health Status
echo "========================================="
echo "3. Health Status"
echo "========================================="
HEALTH_STATUS=$(argocd app get "$APP_NAME" -o json | jq -r '.status.health.status')
echo "Health Status: $HEALTH_STATUS"

case $HEALTH_STATUS in
  Healthy)
    echo -e "${GREEN}✓ Application is healthy${NC}"
    ;;
  Progressing)
    echo -e "${YELLOW}⚠ Application is progressing${NC}"
    echo "This is normal during deployments"
    ;;
  Degraded)
    echo -e "${RED}✗ Application is degraded${NC}"
    echo ""
    echo "Checking resources..."
    argocd app resources "$APP_NAME"
    ;;
  *)
    echo -e "${YELLOW}⚠ Health status: $HEALTH_STATUS${NC}"
    ;;
esac
echo ""

# 4. Recent Sync History
echo "========================================="
echo "4. Recent Sync History"
echo "========================================="
argocd app history "$APP_NAME" | head -10
echo ""

# 5. Current Operation
echo "========================================="
echo "5. Current Operation"
echo "========================================="
OPERATION=$(argocd app get "$APP_NAME" -o json | jq -r '.status.operationState.phase // "None"')
echo "Operation: $OPERATION"

if [ "$OPERATION" != "None" ] && [ "$OPERATION" != "null" ]; then
  echo ""
  echo "Operation details:"
  argocd app get "$APP_NAME" --show-operation
fi
echo ""

# 6. Source Repository
echo "========================================="
echo "6. Source Repository"
echo "========================================="
REPO_URL=$(argocd app get "$APP_NAME" -o json | jq -r '.spec.source.repoURL')
TARGET_REVISION=$(argocd app get "$APP_NAME" -o json | jq -r '.spec.source.targetRevision')
PATH=$(argocd app get "$APP_NAME" -o json | jq -r '.spec.source.path')

echo "Repository: $REPO_URL"
echo "Revision: $TARGET_REVISION"
echo "Path: $PATH"
echo ""

# Check if repo is accessible
echo "Checking repository connectivity..."
if argocd repo get "$REPO_URL" &> /dev/null; then
  echo -e "${GREEN}✓ Repository is accessible${NC}"
else
  echo -e "${RED}✗ Repository is not accessible${NC}"
  echo "Check repository credentials and connectivity"
fi
echo ""

# 7. Sync Policy
echo "========================================="
echo "7. Sync Policy"
echo "========================================="
AUTO_SYNC=$(argocd app get "$APP_NAME" -o json | jq -r '.spec.syncPolicy.automated // "disabled"')
echo "Auto-sync: $AUTO_SYNC"

if [ "$AUTO_SYNC" != "disabled" ] && [ "$AUTO_SYNC" != "null" ]; then
  PRUNE=$(argocd app get "$APP_NAME" -o json | jq -r '.spec.syncPolicy.automated.prune // false')
  SELF_HEAL=$(argocd app get "$APP_NAME" -o json | jq -r '.spec.syncPolicy.automated.selfHeal // false')
  echo "  Prune: $PRUNE"
  echo "  Self-heal: $SELF_HEAL"
fi
echo ""

# 8. Resources
echo "========================================="
echo "8. Managed Resources"
echo "========================================="
argocd app resources "$APP_NAME"
echo ""

# 9. Recent Logs
echo "========================================="
echo "9. Recent Application Logs"
echo "========================================="
argocd app logs "$APP_NAME" --tail=20 || echo "No logs available"
echo ""

# 10. Summary and Recommendations
echo "========================================="
echo "10. Summary & Recommendations"
echo "========================================="

ISSUES=0

# Check sync status
if [ "$SYNC_STATUS" != "Synced" ]; then
  echo -e "${YELLOW}⚠ Application is out of sync${NC}"
  echo "  Action: Run 'argocd app sync $APP_NAME'"
  ISSUES=$((ISSUES + 1))
fi

# Check health status
if [ "$HEALTH_STATUS" != "Healthy" ] && [ "$HEALTH_STATUS" != "Progressing" ]; then
  echo -e "${RED}✗ Application health is $HEALTH_STATUS${NC}"
  echo "  Action: Check individual resources with 'argocd app resources $APP_NAME'"
  ISSUES=$((ISSUES + 1))
fi

# Check auto-sync
if [ "$AUTO_SYNC" = "disabled" ] || [ "$AUTO_SYNC" = "null" ]; then
  echo -e "${YELLOW}⚠ Auto-sync is disabled${NC}"
  echo "  Consider: argocd app set $APP_NAME --sync-policy automated"
fi

if [ $ISSUES -eq 0 ]; then
  echo -e "${GREEN}✓ No issues detected${NC}"
else
  echo ""
  echo "Found $ISSUES issue(s)"
  echo ""
  echo "Troubleshooting commands:"
  echo "  1. View differences: argocd app diff $APP_NAME"
  echo "  2. Sync application: argocd app sync $APP_NAME"
  echo "  3. Refresh git state: argocd app get $APP_NAME --refresh"
  echo "  4. Hard refresh: argocd app get $APP_NAME --hard-refresh"
  echo "  5. View full details: argocd app get $APP_NAME --show-operation"
fi

echo ""
echo "For more information:"
echo "  ArgoCD UI: https://<argocd-server>/applications/$APP_NAME"
echo "  Kubectl: kubectl get application $APP_NAME -n argocd -o yaml"
