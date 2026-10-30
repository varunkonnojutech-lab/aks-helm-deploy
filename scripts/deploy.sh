#!/usr/bin/env bash
# Install (or upgrade) the microservices chart into a cluster.
# Usage: ./scripts/deploy.sh [dev|prod] [namespace]
#   - dev  (default): values-dev.yaml, ClusterIP gateway, no persistence
#   - prod: values-prod.yaml, Ingress + autoscaling (edit it first: ACR,
#     hostname, rabbitmq secret — see the comments at the top of the file)
set -euo pipefail

ENV="${1:-dev}"
NAMESPACE="${2:-microservices}"
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/charts/microservices"

helm lint "$CHART_DIR"
helm upgrade --install shop "$CHART_DIR" \
  -f "$CHART_DIR/values-${ENV}.yaml" \
  --namespace "$NAMESPACE" --create-namespace
kubectl get pods,svc -n "$NAMESPACE"
