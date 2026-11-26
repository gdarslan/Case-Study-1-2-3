#!/usr/bin/env bash
# Local-only demo. Run from any directory; no AWS calls or public ingress.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${DB_PASSWORD:?Set DB_PASSWORD privately}"
: "${HR_ADMIN_TOKEN:?Set HR_ADMIN_TOKEN privately (at least 32 characters)}"
: "${HR_VIEWER_TOKEN:?Set HR_VIEWER_TOKEN privately (at least 32 characters)}"
if [[ ${#HR_ADMIN_TOKEN} -lt 32 || ${#HR_VIEWER_TOKEN} -lt 32 || "$HR_ADMIN_TOKEN" == "$HR_VIEWER_TOKEN" ]]; then
  echo "Use two distinct access tokens of at least 32 characters." >&2
  exit 1
fi
for command in minikube kubectl; do command -v "$command" >/dev/null; done
PROFILE=innovatech-hr
minikube -p "$PROFILE" start --driver=docker --cni=calico --memory=4096 --cpus=2
minikube -p "$PROFILE" addons enable metrics-server
minikube -p "$PROFILE" image build -t innovatech/hr-backend:latest app/backend/
minikube -p "$PROFILE" image build -t innovatech/hr-frontend:latest app/frontend/
k() { kubectl --context "$PROFILE" "$@"; }
k apply -f k8s/namespace.yaml
# Avoid overwriting a database password across reruns of a persistent cluster.
if ! k get secret hr-db-secret -n hr-app >/dev/null 2>&1; then
  k create secret generic hr-db-secret -n hr-app \
    --from-literal=DB_HOST=postgres --from-literal=DB_PORT=5432 \
    --from-literal=DB_NAME=innovatech --from-literal=DB_USER=innovatech_admin \
    --from-literal=DB_PASS="$DB_PASSWORD"
fi
k create secret generic hr-api-secret -n hr-app \
  --from-literal=HR_ADMIN_TOKEN="$HR_ADMIN_TOKEN" \
  --from-literal=HR_VIEWER_TOKEN="$HR_VIEWER_TOKEN" \
  --dry-run=client -o yaml | k apply -f -
k apply -f k8s/network-policy.yaml
k apply -f k8s/rbac.yaml
k apply -f k8s/postgres-deployment.yaml
k wait --for=condition=available deployment/postgres -n hr-app --timeout=120s
k delete job db-init -n hr-app --ignore-not-found=true
k apply -f k8s/db-init-job.yaml
k wait --for=condition=complete job/db-init -n hr-app --timeout=120s
# Render local images to stdin. Never edit the tracked Kubernetes manifests.
sed '/image: .*hr-backend/c\          image: innovatech/hr-backend:latest\n          imagePullPolicy: Never' k8s/backend-deployment.yaml | k apply -f -
sed '/image: .*hr-frontend/c\          image: innovatech/hr-frontend:latest\n          imagePullPolicy: Never' k8s/frontend-deployment.yaml | k apply -f -
k apply -f k8s/hpa.yaml
k rollout restart deployment/hr-backend deployment/hr-frontend -n hr-app
k rollout status deployment/hr-backend -n hr-app --timeout=180s
k rollout status deployment/hr-frontend -n hr-app --timeout=180s
echo "Local demo ready. Open http://127.0.0.1:8080 after running:"
echo "kubectl --context $PROFILE -n hr-app port-forward svc/hr-frontend 8080:80 --address 127.0.0.1"
