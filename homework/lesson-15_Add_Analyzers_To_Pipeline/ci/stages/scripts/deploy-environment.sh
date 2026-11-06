#!/usr/bin/env bash
# Deploy one persistent local environment through the scoped K3s CI identity.
set -euo pipefail

environment_name=${1:?Usage: deploy-environment.sh <stage|prod> <host-port> <image-reference>}
node_port=${2:?Usage: deploy-environment.sh <stage|prod> <node-port> <image-reference>}
app_image_ref=${3:?Usage: deploy-environment.sh <stage|prod> <host-port> <image-reference>}

case "$environment_name" in
  stage|prod) ;;
  *) echo "Environment must be stage or prod." >&2; exit 2 ;;
esac
[[ "$node_port" =~ ^30[0-9]{3}$ ]] || { echo "NodePort must be in the local 30000 range." >&2; exit 2; }
: "${KUBECONFIG:=/etc/kubernetes/deployer.conf}"
export KUBECONFIG
namespace="cocktail-${environment_name}"
template="$(dirname "$0")/environment.yaml.template"
rollout_timeout="${ROLLOUT_TIMEOUT:-180s}"
[[ -r "$KUBECONFIG" ]] || { echo "Scoped deployment kubeconfig is unavailable." >&2; exit 1; }
[[ -f "$template" ]] || { echo "Kubernetes template is unavailable: $template" >&2; exit 1; }

application_name="cocktail-${environment_name}-search"
database_name="cocktail-${environment_name}-postgres"
had_revision=false
previous_revision=""
if kubectl -n "$namespace" get deployment "$application_name" >/dev/null 2>&1; then
  had_revision=true
  previous_revision="$(kubectl -n "$namespace" get deployment "$application_name" \
    -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')"
fi

# The StatefulSet/PVC is applied but never deleted during normal deployment.
sed -e "s|__NAMESPACE__|${namespace}|g" \
    -e "s|__ENVIRONMENT__|${environment_name}|g" \
    -e "s|__NODE_PORT__|${node_port}|g" \
    -e "s|__APP_IMAGE_REF__|${app_image_ref}|g" "$template" | kubectl apply -f -
kubectl -n "$namespace" rollout status "statefulset/${database_name}" --timeout="$rollout_timeout"

if ! kubectl -n "$namespace" rollout status "deployment/${application_name}" --timeout="$rollout_timeout"; then
  echo "${environment_name} rollout failed; restoring the preceding application revision." >&2
  if [[ "$had_revision" == true && "$previous_revision" =~ ^[0-9]+$ ]]; then
    kubectl -n "$namespace" rollout undo "deployment/${application_name}" --to-revision="$previous_revision"
    kubectl -n "$namespace" rollout status "deployment/${application_name}" --timeout="$rollout_timeout"
  else
    echo "No preceding application revision exists; PostgreSQL PVC remains for diagnosis." >&2
  fi
  exit 1
fi

echo "${environment_name} Kubernetes rollout is healthy. Database PVC was retained."
