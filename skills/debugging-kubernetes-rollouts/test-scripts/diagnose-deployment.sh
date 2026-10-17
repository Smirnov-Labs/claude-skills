#!/usr/bin/env bash
#
# Kubernetes Deployment Diagnostic Script
#
# Systematically diagnoses deployment issues in Kubernetes
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage
usage() {
  echo "Usage: $0 -d DEPLOYMENT -n NAMESPACE [-c CONTEXT]"
  echo ""
  echo "Options:"
  echo "  -d DEPLOYMENT  Deployment name"
  echo "  -n NAMESPACE   Namespace"
  echo "  -c CONTEXT     Kubectl context (optional)"
  echo ""
  echo "Example:"
  echo "  $0 -d api -n production"
  exit 1
}

# Parse arguments
while getopts "d:n:c:h" opt; do
  case $opt in
    d) DEPLOYMENT="$OPTARG" ;;
    n) NAMESPACE="$OPTARG" ;;
    c) CONTEXT="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [ -z "$DEPLOYMENT" ] || [ -z "$NAMESPACE" ]; then
  usage
fi

# Set context if provided
if [ -n "$CONTEXT" ]; then
  KUBECTL_ARGS="--context=$CONTEXT"
else
  KUBECTL_ARGS=""
fi

echo "========================================="
echo "Kubernetes Deployment Diagnostics"
echo "========================================="
echo "Deployment: $DEPLOYMENT"
echo "Namespace: $NAMESPACE"
if [ -n "$CONTEXT" ]; then
  echo "Context: $CONTEXT"
fi
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}✗ kubectl not found${NC}"
  exit 1
fi

echo -e "${GREEN}✓ kubectl found${NC}"
echo ""

# Check if deployment exists
echo "Checking if deployment exists..."
if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS &> /dev/null; then
  echo -e "${RED}✗ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Deployment exists${NC}"
echo ""

# 1. Check deployment status
echo "========================================="
echo "1. Deployment Status"
echo "========================================="
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS
echo ""

# Check rollout status
echo "Rollout status:"
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS || true
echo ""

# 2. Check pods
echo "========================================="
echo "2. Pod Status"
echo "========================================="
PODS=$(kubectl get pods -n "$NAMESPACE" $KUBECTL_ARGS -l "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.spec.selector.matchLabels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')" -o name 2>/dev/null || echo "")

if [ -z "$PODS" ]; then
  echo -e "${RED}✗ No pods found for deployment${NC}"
  echo ""
  echo "Checking selector:"
  kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.spec.selector.matchLabels}' | jq .
  echo ""
else
  kubectl get pods -n "$NAMESPACE" $KUBECTL_ARGS -l "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.spec.selector.matchLabels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')"
  echo ""
fi

# 3. Check recent events
echo "========================================="
echo "3. Recent Events"
echo "========================================="
kubectl get events -n "$NAMESPACE" $KUBECTL_ARGS --sort-by='.lastTimestamp' | grep "$DEPLOYMENT" | tail -10
echo ""

# 4. Check for problem pods
echo "========================================="
echo "4. Problem Pods Analysis"
echo "========================================="

PROBLEM_PODS=$(kubectl get pods -n "$NAMESPACE" $KUBECTL_ARGS -l "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.spec.selector.matchLabels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')" -o json 2>/dev/null | jq -r '.items[] | select(.status.phase != "Running" or (.status.containerStatuses[]? | select(.ready == false))) | .metadata.name' || echo "")

if [ -z "$PROBLEM_PODS" ]; then
  echo -e "${GREEN}✓ All pods are running and ready${NC}"
else
  echo -e "${YELLOW}⚠ Found problem pods:${NC}"
  echo "$PROBLEM_PODS"
  echo ""

  for POD in $PROBLEM_PODS; do
    echo "--- Pod: $POD ---"
    echo ""

    # Check pod phase
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.status.phase}')
    echo "Phase: $PHASE"

    # Check container statuses
    echo "Container statuses:"
    kubectl get pod "$POD" -n "$NAMESPACE" $KUBECTL_ARGS -o json | jq -r '.status.containerStatuses[]? | "  \(.name): \(.state | keys[0]) - Ready: \(.ready)"'
    echo ""

    # Check for common issues
    REASON=$(kubectl get pod "$POD" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
    if [ -n "$REASON" ]; then
      echo -e "${RED}Issue: $REASON${NC}"

      case $REASON in
        ImagePullBackOff|ErrImagePull)
          echo "Image issue detected. Checking image..."
          IMAGE=$(kubectl get pod "$POD" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.spec.containers[0].image}')
          echo "  Image: $IMAGE"
          echo "  Suggestion: Verify image exists and pull secrets are correct"
          ;;
        CrashLoopBackOff)
          echo "Container crashing. Last 20 lines of logs:"
          kubectl logs "$POD" -n "$NAMESPACE" $KUBECTL_ARGS --previous --tail=20 2>/dev/null || kubectl logs "$POD" -n "$NAMESPACE" $KUBECTL_ARGS --tail=20 2>/dev/null || echo "  No logs available"
          ;;
        CreateContainerConfigError|CreateContainerError)
          echo "Container configuration error."
          echo "Checking pod description:"
          kubectl describe pod "$POD" -n "$NAMESPACE" $KUBECTL_ARGS | grep -A 10 "Events:"
          ;;
      esac
    fi
    echo ""
  done
fi

# 5. Check ReplicaSets
echo "========================================="
echo "5. ReplicaSet Status"
echo "========================================="
kubectl get rs -n "$NAMESPACE" $KUBECTL_ARGS | grep "$DEPLOYMENT"
echo ""

# 6. Check resource quotas
echo "========================================="
echo "6. Resource Quotas & Limits"
echo "========================================="
QUOTAS=$(kubectl get resourcequota -n "$NAMESPACE" $KUBECTL_ARGS -o json 2>/dev/null | jq -r '.items[].metadata.name' || echo "")
if [ -n "$QUOTAS" ]; then
  kubectl describe resourcequota -n "$NAMESPACE" $KUBECTL_ARGS
else
  echo "No resource quotas set"
fi
echo ""

# 7. Check service connectivity
echo "========================================="
echo "7. Service Configuration"
echo "========================================="
SERVICES=$(kubectl get svc -n "$NAMESPACE" $KUBECTL_ARGS -o json | jq -r --arg dep "$DEPLOYMENT" '.items[] | select(.spec.selector | to_entries | any(.key as $k | .value as $v | $dep | contains($k))) | .metadata.name' 2>/dev/null || echo "")

if [ -n "$SERVICES" ]; then
  for SVC in $SERVICES; do
    echo "Service: $SVC"
    kubectl get svc "$SVC" -n "$NAMESPACE" $KUBECTL_ARGS
    echo ""

    echo "Endpoints:"
    kubectl get endpoints "$SVC" -n "$NAMESPACE" $KUBECTL_ARGS
    echo ""
  done
else
  echo -e "${YELLOW}⚠ No services found for this deployment${NC}"
  echo ""
fi

# 8. Summary and Recommendations
echo "========================================="
echo "8. Summary & Recommendations"
echo "========================================="

# Check replica status
DESIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.spec.replicas}')
READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" $KUBECTL_ARGS -o jsonpath='{.status.readyReplicas}')

echo "Replicas: $READY/$DESIRED ready"

if [ "$READY" = "$DESIRED" ]; then
  echo -e "${GREEN}✓ Deployment is healthy${NC}"
else
  echo -e "${RED}✗ Deployment is not healthy${NC}"
  echo ""
  echo "Troubleshooting steps:"
  echo "  1. Check pod logs: kubectl logs <pod-name> -n $NAMESPACE"
  echo "  2. Describe problem pods: kubectl describe pod <pod-name> -n $NAMESPACE"
  echo "  3. Check recent events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
  echo "  4. Verify image: docker pull <image> (if accessible)"
  echo "  5. Check resource limits: kubectl top pods -n $NAMESPACE"
fi

echo ""
echo "For more details, run:"
echo "  kubectl describe deployment $DEPLOYMENT -n $NAMESPACE"
echo "  kubectl logs -l app=$DEPLOYMENT -n $NAMESPACE --tail=50"
