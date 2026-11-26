resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks"
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids         = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    security_group_ids = [aws_security_group.eks_cluster.id]
    # Private access keeps control plane traffic inside VPC (ZTA REQ-NCA-P3-06)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Required for EKS access entries API (used instead of legacy aws-auth ConfigMap)
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  # Ship control plane logs to CloudWatch (REQ-NCA-P3-05)
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# Managed node group — nodes live in private subnets only
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.eks_node_instance_type]

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read,
  ]
}

# Core add-ons
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

# EBS CSI driver — required for PersistentVolumeClaims
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"
  depends_on   = [aws_eks_node_group.main]
}

# ─── EKS Access Entries (replaces legacy aws-auth ConfigMap) ────────────────
# Maps IAM roles to Kubernetes RBAC groups (REQ-NCA-P3-10, P3-11)

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.platform_admin.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.platform_admin.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
  depends_on    = [aws_eks_access_entry.admin]
}

resource "aws_eks_access_entry" "developer" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.platform_developer.arn
  type              = "STANDARD"
  kubernetes_groups = ["innovatech-developers"]
}

resource "aws_eks_access_entry" "readonly" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.platform_readonly.arn
  type              = "STANDARD"
  kubernetes_groups = ["innovatech-readonly"]
}

# ─── ECR Repositories ───────────────────────────────────────────────────────

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}/hr-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}/hr-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
