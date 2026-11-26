data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }


# S3 BUCKET  (alert log storage)


resource "aws_s3_bucket" "soar_logs" {
  bucket        = "soar-event-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "soar-event-logs" }
}


# IAM — Lambda response actions


resource "aws_iam_role" "lambda_role" {
  name = "soar-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "soar-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.soar_logs.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

# LAMBDA: SES ALERT


data "archive_file" "ses_lambda" {
  type        = "zip"
  source_file = "${path.module}/soar/ses_handler.py"
  output_path = "${path.module}/soar/ses_handler.zip"
}

resource "aws_lambda_function" "ses_alert" {
  function_name    = "soar-ses-alert"
  role             = aws_iam_role.lambda_role.arn
  handler          = "ses_handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ses_lambda.output_path
  source_code_hash = data.archive_file.ses_lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      SENDER_EMAIL    = var.ses_sender_email
      RECIPIENT_EMAIL = var.ses_recipient_email
    }
  }
}

# LAMBDA: S3 LOG


data "archive_file" "s3_lambda" {
  type        = "zip"
  source_file = "${path.module}/soar/s3_handler.py"
  output_path = "${path.module}/soar/s3_handler.zip"
}

resource "aws_lambda_function" "s3_log" {
  function_name    = "soar-s3-log"
  role             = aws_iam_role.lambda_role.arn
  handler          = "s3_handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.s3_lambda.output_path
  source_code_hash = data.archive_file.s3_lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.soar_logs.bucket
    }
  }
}


# NETWORKING — dedicated VPC for ECS


resource "aws_vpc" "soar" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "soar-vpc" }
}

resource "aws_internet_gateway" "soar" {
  vpc_id = aws_vpc.soar.id
  tags   = { Name = "soar-igw" }
}

resource "aws_subnet" "soar_a" {
  vpc_id                  = aws_vpc.soar.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "soar-public-a" }
}

resource "aws_subnet" "soar_b" {
  vpc_id                  = aws_vpc.soar.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = { Name = "soar-public-b" }
}

resource "aws_route_table" "soar_public" {
  vpc_id = aws_vpc.soar.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.soar.id
  }

  tags = { Name = "soar-public-rt" }
}

resource "aws_route_table_association" "soar_a" {
  subnet_id      = aws_subnet.soar_a.id
  route_table_id = aws_route_table.soar_public.id
}

resource "aws_route_table_association" "soar_b" {
  subnet_id      = aws_subnet.soar_b.id
  route_table_id = aws_route_table.soar_public.id
}

# SECURITY GROUPS


resource "aws_security_group" "soar_alb" {
  name   = "soar-alb-sg"
  vpc_id = aws_vpc.soar.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.alert_source_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "soar_ecs" {
  name   = "soar-ecs-sg"
  vpc_id = aws_vpc.soar.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.soar_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ECR REPOSITORY


resource "aws_ecr_repository" "soar_processor" {
  name                 = "soar-processor"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = { Name = "soar-processor" }
}


# ALB  (public HTTPS endpoint for /alert)


resource "aws_lb" "soar" {
  name               = "soar-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.soar_alb.id]
  subnets            = [aws_subnet.soar_a.id, aws_subnet.soar_b.id]

  tags = { Name = "soar-alb" }
}

resource "aws_lb_target_group" "soar" {
  name        = "soar-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.soar.id
  target_type = "ip"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "soar" {
  load_balancer_arn = aws_lb.soar.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.soar_tls_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.soar.arn
  }
}


# IAM — ECS task execution + task roles


resource "aws_iam_role" "ecs_task_exec" {
  name = "soar-ecs-task-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "soar_token_read" {
  name = "soar-token-read"
  role = aws_iam_role.ecs_task_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = var.soar_api_token_secret_arn
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "soar-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "soar-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [aws_lambda_function.ses_alert.arn, aws_lambda_function.s3_log.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

# ECS CLUSTER + TASK DEFINITION + SERVICE


resource "aws_cloudwatch_log_group" "soar_ecs" {
  name              = "/ecs/soar-processor"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "soar" {
  name = "soar-cluster"
  tags = { Name = "soar-cluster" }
}

resource "aws_ecs_task_definition" "soar_processor" {
  family                   = "soar-processor"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "soar-processor"
    image     = "${aws_ecr_repository.soar_processor.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 5000
      protocol      = "tcp"
    }]

    environment = [
      { name = "SES_LAMBDA_ARN", value = aws_lambda_function.ses_alert.arn },
      { name = "S3_LAMBDA_ARN", value = aws_lambda_function.s3_log.arn },
      { name = "AWS_DEFAULT_REGION", value = var.aws_region }
    ]

    secrets = [{ name = "SOAR_API_TOKEN", valueFrom = var.soar_api_token_secret_arn }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.soar_ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "soar_processor" {
  name            = "soar-processor"
  cluster         = aws_ecs_cluster.soar.id
  task_definition = aws_ecs_task_definition.soar_processor.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.soar_a.id, aws_subnet.soar_b.id]
    security_groups  = [aws_security_group.soar_ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.soar.arn
    container_name   = "soar-processor"
    container_port   = 5000
  }

  depends_on = [aws_lb_listener.soar, aws_iam_role_policy.soar_token_read]
}


# OUTPUTS


output "soar_endpoint" {
  description = "POST an alert JSON to this endpoint to trigger SOAR"
  value       = "http://${aws_lb.soar.dns_name}/alert"
}

output "ecr_repository_url" {
  description = "Push the soar-processor Docker image here before the ECS service can start"
  value       = aws_ecr_repository.soar_processor.repository_url
}

output "s3_bucket_name" {
  description = "Alert logs are stored in this S3 bucket"
  value       = aws_s3_bucket.soar_logs.bucket
}
