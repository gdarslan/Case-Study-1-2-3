# ECR repositories for HR app Docker images (REQ-NCA-P3-03)
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
