#!/bin/bash
# Local deployment using minikube — use this instead of deploy.sh when AWS EKS is not available
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

: "${DB_PASSWORD:?Set DB_PASSWORD to a strong local demo password before running}"

# ─── Start minikube ──────────────────────────────────────────────────────────
info "Starting minikube..."
minikube start --driver=docker --memory=4096 --cpus=2
minikube addons enable ingress
minikube addons enable metrics-server
success "Minikube ready."

# ─── Build images inside minikube (no ECR needed) ───────────────────────────
info "Building images inside minikube..."
eval $(minikube docker-env)
docker build -t innovatech/hr-backend:latest  app/backend/
docker build -t innovatech/hr-frontend:latest app/frontend/
success "Images built."

# ─── Patch deployments to use local images ───────────────────────────────────
sed -i "s|image:.*hr-backend.*|image: innovatech/hr-backend:latest|g"  k8s/backend-deployment.yaml
sed -i "s|image:.*hr-frontend.*|image: innovatech/hr-frontend:latest|g" k8s/frontend-deployment.yaml

# Add imagePullPolicy: Never so minikube uses local images
sed -i '/image: innovatech\/hr-backend/a\          imagePullPolicy: Never' k8s/backend-deployment.yaml
sed -i '/image: innovatech\/hr-frontend/a\          imagePullPolicy: Never' k8s/frontend-deployment.yaml

# ─── Apply manifests ─────────────────────────────────────────────────────────
info "Applying namespace..."
kubectl apply -f k8s/namespace.yaml

info "Creating database secret..."
kubectl create secret generic hr-db-secret \
  --namespace hr-app \
  --from-literal=DB_HOST="postgres" \
  --from-literal=DB_PORT="5432" \
  --from-literal=DB_NAME="innovatech" \
  --from-literal=DB_USER="innovatech_admin" \
  --from-literal=DB_PASS="$DB_PASSWORD" \
  --save-config --dry-run=client -o yaml | kubectl apply -f -

info "Deploying PostgreSQL..."
kubectl apply -f k8s/postgres-deployment.yaml

info "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=available deployment/postgres -n hr-app --timeout=120s

info "Running database init job..."
kubectl delete job db-init -n hr-app --ignore-not-found=true
kubectl apply -f k8s/db-init-job.yaml
kubectl wait --for=condition=complete job/db-init -n hr-app --timeout=120s

info "Deploying backend and frontend..."
kubectl apply -f k8s/network-policy.yaml
kubectl apply -f k8s/rbac.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml

info "Waiting for rollout..."
kubectl rollout status deployment/hr-backend  -n hr-app --timeout=180s
kubectl rollout status deployment/hr-frontend -n hr-app --timeout=180s

# ─── Print access URL ────────────────────────────────────────────────────────
MINIKUBE_IP=$(minikube ip)
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Local deployment complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  HR Portal : ${BLUE}http://$MINIKUBE_IP${NC}"
echo -e "  API docs  : ${BLUE}http://$MINIKUBE_IP/api/docs${NC}"
echo ""
echo "  To open in browser: minikube service hr-frontend -n hr-app"
