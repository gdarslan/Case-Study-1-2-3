#!/bin/bash
# Full end-to-end deployment script for Innovatech HR platform
# Run from the repo root after setting TF_VAR_db_password

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Prerequisites ───────────────────────────────────────────────────────────

info "Checking prerequisites..."
for cmd in aws terraform kubectl docker; do
  command -v "$cmd" &>/dev/null || error "$cmd is not installed. Please install it first."
done

[ -z "${TF_VAR_db_password:-}" ] && error "TF_VAR_db_password is not set. Run: export TF_VAR_db_password='YourPassword'"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
success "AWS account: $AWS_ACCOUNT_ID"

# ─── Step 1: Terraform ───────────────────────────────────────────────────────

info "Running Terraform..."
cd terraform
terraform init -upgrade -input=false
terraform apply -auto-approve -input=false
success "Terraform apply complete."

# Read outputs
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
AWS_REGION=$(grep 'aws_region' terraform.tfvars | awk -F'"' '{print $2}')
AWS_REGION=${AWS_REGION:-eu-central-1}
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
RDS_HOST=$(echo "$RDS_ENDPOINT" | cut -d: -f1)
RDS_PORT=$(echo "$RDS_ENDPOINT" | cut -d: -f2)
ECR_BACKEND=$(terraform output -raw ecr_backend_url)
ECR_FRONTEND=$(terraform output -raw ecr_frontend_url)
FLUENT_BIT_ROLE=$(terraform output -raw fluent_bit_role_arn)

cd ..
success "Terraform outputs collected."

# ─── Step 2: Configure kubectl ───────────────────────────────────────────────

info "Configuring kubectl for EKS cluster: $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
success "kubectl configured."

# ─── Step 3: Build and push Docker images ────────────────────────────────────

info "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

info "Building and pushing backend image..."
docker build -t "$ECR_BACKEND:latest" app/backend/
docker push "$ECR_BACKEND:latest"
success "Backend image pushed."

info "Building and pushing frontend image..."
docker build -t "$ECR_FRONTEND:latest" app/frontend/
docker push "$ECR_FRONTEND:latest"
success "Frontend image pushed."

# ─── Step 4: Update K8s manifests with real image URLs ───────────────────────

info "Patching image URLs in K8s manifests..."
# Replace either the placeholder or a previously set ECR URL — idempotent on re-runs
sed -i "s|image:.*hr-backend.*|image: $ECR_BACKEND:latest|g" k8s/backend-deployment.yaml
sed -i "s|image:.*hr-frontend.*|image: $ECR_FRONTEND:latest|g" k8s/frontend-deployment.yaml
success "Image URLs patched."

# ─── Step 5: Apply namespace and secret ──────────────────────────────────────

info "Applying namespace..."
kubectl apply -f k8s/namespace.yaml

info "Creating database secret from Terraform outputs..."
kubectl create secret generic hr-db-secret \
  --namespace hr-app \
  --from-literal=DB_HOST="$RDS_HOST" \
  --from-literal=DB_PORT="${RDS_PORT:-5432}" \
  --from-literal=DB_NAME="innovatech" \
  --from-literal=DB_USER="innovatech_admin" \
  --from-literal=DB_PASS="$TF_VAR_db_password" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -
success "Secret created."

# ─── Step 6: Deploy application ──────────────────────────────────────────────

info "Applying RBAC..."
kubectl apply -f k8s/rbac.yaml

info "Applying network policies..."
kubectl apply -f k8s/network-policy.yaml

info "Deploying backend..."
kubectl apply -f k8s/backend-deployment.yaml

info "Deploying frontend..."
kubectl apply -f k8s/frontend-deployment.yaml

info "Applying ingress..."
kubectl apply -f k8s/ingress.yaml

success "Application deployed."

# ─── Step 7: Run database init job ───────────────────────────────────────────

info "Running database init job..."
kubectl delete job db-init -n hr-app --ignore-not-found=true
kubectl apply -f k8s/db-init-job.yaml
kubectl wait --for=condition=complete job/db-init -n hr-app --timeout=120s
success "Database initialised."

# ─── Step 8: Deploy Fluent Bit logging ───────────────────────────────────────

info "Deploying Fluent Bit logging..."
# Patch Fluent Bit service account with the IRSA role ARN from Terraform
sed -i "s|<FLUENT_BIT_ROLE_ARN>|$FLUENT_BIT_ROLE|g" k8s/logging/fluent-bit-serviceaccount.yaml

kubectl apply -f k8s/logging/fluent-bit-namespace.yaml
kubectl apply -f k8s/logging/fluent-bit-serviceaccount.yaml
kubectl apply -f k8s/logging/fluent-bit-configmap.yaml
kubectl apply -f k8s/logging/fluent-bit-daemonset.yaml
success "Fluent Bit deployed."

# ─── Step 9: Wait for rollout and print URL ──────────────────────────────────

info "Waiting for deployments to roll out..."
kubectl rollout status deployment/hr-backend  -n hr-app --timeout=180s
kubectl rollout status deployment/hr-frontend -n hr-app --timeout=180s

info "Waiting for ALB to become available (this takes ~60s)..."
sleep 60

ALB_URL=$(kubectl get ingress hr-app-ingress -n hr-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Deployment complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  HR Portal : ${BLUE}http://$ALB_URL${NC}"
echo -e "  API docs  : ${BLUE}http://$ALB_URL/api/docs${NC}"
echo -e "  Cluster   : $CLUSTER_NAME"
echo -e "  Region    : $AWS_REGION"
echo ""
