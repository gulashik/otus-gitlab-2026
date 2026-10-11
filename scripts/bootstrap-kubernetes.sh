#!/usr/bin/env bash
# Create the local, namespace-scoped deployment identity without printing it.
set -euo pipefail

readonly kubeconfig_dir="local/kubeconfig"
readonly deployer_kubeconfig_path="${kubeconfig_dir}/deployer.conf"
readonly freelens_kubeconfig_path="${kubeconfig_dir}/freelens-admin.conf"
readonly service_account="cocktail-deployer"
readonly identity_namespace="cocktail-stage"
readonly namespaces=(cocktail-stage cocktail-prod)

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
command -v podman >/dev/null || fail "podman is required"

for attempt in $(seq 1 60); do
  if podman compose exec -T k3s env KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
    kubectl get --raw=/readyz >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    fail "K3s did not become ready; start it with: podman compose up -d k3s"
  fi
  sleep 2
done

for namespace in "${namespaces[@]}"; do
  podman compose exec -T k3s kubectl create namespace "$namespace" \
    --dry-run=client -o yaml | podman compose exec -T k3s kubectl apply -f - >/dev/null
done

podman compose exec -T k3s kubectl -n "$identity_namespace" create serviceaccount "$service_account" \
  --dry-run=client -o yaml | podman compose exec -T k3s kubectl apply -f - >/dev/null

for namespace in "${namespaces[@]}"; do
  cat <<YAML | podman compose exec -T k3s kubectl apply -f - >/dev/null
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cocktail-deployer
  namespace: ${namespace}
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets", "services", "pods", "pods/log", "persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "deployments/scale", "deployments/status", "statefulsets", "statefulsets/status", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cocktail-deployer
  namespace: ${namespace}
subjects:
  - kind: ServiceAccount
    name: ${service_account}
    namespace: ${identity_namespace}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cocktail-deployer
YAML
done

# A local token and kubeconfig are deliberately ignored.
token="$(podman compose exec -T k3s kubectl -n "$identity_namespace" create token "$service_account" --duration=8760h)"
ca_data="$(podman compose exec -T k3s cat /var/lib/rancher/k3s/server/tls/server-ca.crt | base64 | tr -d '\n')"
[[ -n "$token" && -n "$ca_data" ]] || fail "Could not generate local deployment access"

umask 077
mkdir -p "$kubeconfig_dir"
deployer_temporary_path="${deployer_kubeconfig_path}.tmp"
cat >"$deployer_temporary_path" <<YAML
apiVersion: v1
kind: Config
clusters:
  - name: local-k3s
    cluster:
      certificate-authority-data: ${ca_data}
      server: https://k3s.localhost:6443
contexts:
  - name: cocktail-deployer
    context:
      cluster: local-k3s
      namespace: cocktail-stage
      user: cocktail-deployer
current-context: cocktail-deployer
users:
  - name: cocktail-deployer
    user:
      token: ${token}
YAML
mv "$deployer_temporary_path" "$deployer_kubeconfig_path"
chmod 0600 "$deployer_kubeconfig_path"

# K3s keeps its built-in administrator configuration inside the container.
# Rewrite only its internal loopback API address so a host desktop client can
# use the TLS name explicitly configured in compose.yml.
freelens_temporary_path="${freelens_kubeconfig_path}.tmp"
podman compose exec -T k3s cat /etc/rancher/k3s/k3s.yaml \
  | sed 's#server: https://127.0.0.1:6443#server: https://k3s.localhost:6443#' \
  >"$freelens_temporary_path"
grep -Fq 'server: https://k3s.localhost:6443' "$freelens_temporary_path" \
  || fail "Could not prepare the host-reachable Freelens administrator kubeconfig"
mv "$freelens_temporary_path" "$freelens_kubeconfig_path"
chmod 0600 "$freelens_kubeconfig_path"

printf 'Kubernetes bootstrap complete. Restricted deployer kubeconfig and full-access local Freelens kubeconfig written without printing credentials.\n'
