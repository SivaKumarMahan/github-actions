#!/usr/bin/env bash
# Deploy the Helm chart to one environment (namespace), then run the smoke test.
#
# Usage: deploy.sh <staging|production> <image-repository> <image-tag>
#
# Uses the current kubectl context. In GitHub Actions that is the AKS cluster
# (az aks get-credentials + kubelogin). Locally it can be a kind cluster.
# Optional environment variables:
#   APP_IDENTITY_CLIENT_ID  client ID of the app's managed identity (turns on Workload ID)
#   HELM_TIMEOUT            how long to wait for the rollout (default 5m)
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <staging|production> <image-repository> <image-tag>" >&2
  exit 2
fi

environment=$1
image_repository=$2
image_tag=$3

case "$environment" in
  staging | production) ;;
  *) echo "unknown environment: $environment" >&2; exit 2 ;;
esac

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../chart" && pwd)"
release="p3-aks-app"
namespace="$environment"

extra_args=()
if [[ -n "${APP_IDENTITY_CLIENT_ID:-}" ]]; then
  extra_args+=(--set workloadIdentity.enabled=true
    --set-string "workloadIdentity.clientId=${APP_IDENTITY_CLIENT_ID}")
fi

echo "Deploying ${image_repository}:${image_tag} to namespace ${namespace}"

# --atomic: if the rollout does not become ready in time, Helm rolls back to the
# previous release, so a failed deploy never stays half applied.
helm upgrade --install "$release" "$chart_dir" \
  --namespace "$namespace" \
  --values "${chart_dir}/values-${environment}.yaml" \
  --set-string "image.repository=${image_repository}" \
  --set-string "image.tag=${image_tag}" \
  --atomic --wait --timeout "${HELM_TIMEOUT:-5m}" \
  --history-max 10 \
  "${extra_args[@]}"

kubectl --namespace "$namespace" rollout status "deployment/${release}" --timeout=60s

# Smoke test: a pod calls /health through the Service and checks the version.
# --atomic only covers the rollout. If the smoke test fails, roll back here too.
if ! helm test "$release" --namespace "$namespace" --logs --timeout 2m; then
  echo "Smoke test failed, rolling back ${release} in ${namespace}" >&2
  helm rollback "$release" --namespace "$namespace" --wait --timeout "${HELM_TIMEOUT:-5m}"
  exit 1
fi
