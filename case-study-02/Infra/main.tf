
data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  name = var.project_name
  az1  = data.aws_availability_zones.available.names[0]
  az2  = data.aws_availability_zones.available.names[1]
}


# VPC one vpc
# CIDR 10.0.0.0/16 gives us 65 536 IP addresses to work with.


resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "main-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main-igw" }
}


# SUBNETS  (3-tier layout, spread over 2 AZs)
#
#   Public  10.0.1.0/24  10.0.2.0/24   <- ALB, Bastion, Monitoring
#   App     10.0.11.0/24 10.0.12.0/24  <- Web servers (private)
#   DB      10.0.21.0/24 10.0.22.0/24  <- RDS (private)


resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags                    = { Name = "public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = local.az2
  map_public_ip_on_launch = true
  tags                    = { Name = "public-b" }
}

resource "aws_subnet" "app_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = local.az1
  tags              = { Name = "app-private-a" }
}

resource "aws_subnet" "app_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = local.az2
  tags              = { Name = "app-private-b" }
}

resource "aws_subnet" "db_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = local.az1
  tags              = { Name = "db-private-a" }
}

resource "aws_subnet" "db_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = local.az2
  tags              = { Name = "db-private-b" }
}

# ──
# NAT GATEWAY
# Private subnets cannot reach the internet directly.
# The NAT gateway sits in the public subnet and forwards
# outbound traffic on behalf of private instances.
#****

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags   = { Name = "nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "main-nat" }
}


# ROUTE TABLES
# Public  -> internet gateway  (0.0.0.0/0 via IGW)
# Private -> NAT gateway       (0.0.0.0/0 via NAT)


resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "private-rt" }
}

resource "aws_route_table_association" "app_private_a" {
  subnet_id      = aws_subnet.app_private_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "app_private_b" {
  subnet_id      = aws_subnet.app_private_b.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "db_private_a" {
  subnet_id      = aws_subnet.db_private_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "db_private_b" {
  subnet_id      = aws_subnet.db_private_b.id
  route_table_id = aws_route_table.private_rt.id
}

# BASTION HOST
# A small EC2 in the public subnet used to SSH into
# private instances (app servers, etc.) for debugging.


resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH from anywhere to the bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bastion-sg" }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_a.id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = { Name = "bastion" }
}


# SECURITY GROUPS
#
# Traffic flow:
#   Internet -> ALB (port 80)
#   ALB      -> App servers (port 80)
#   Bastion  -> App servers (port 22, SSH)
#   App      -> RDS (port 3306, MySQL)
#   Bastion  -> RDS (port 3306, for manual queries)


resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP traffic from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Allow HTTP from ALB and SSH from Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  ingress {
    description     = "Node exporter scrape from monitoring server"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "app-sg" }
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow MySQL from app servers and Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from app and bastion"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id, aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "db-sg" }
}

# LOAD BALANCER
# The ALB distributes incoming HTTP traffic across
# all healthy app server instances.


resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags               = { Name = "app-alb" }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "app-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# AUTO SCALING GROUP
# Automatically adds or removes EC2 instances based on load.
# Min 2 instances (high availability), max 4 (cost control).
# Each new instance runs the user_data script on startup.


resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  # This script runs automatically when a new instance starts
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx

    systemctl enable nginx
    systemctl start nginx

    # Simple web page showing the hostname of this instance
    echo "<h1>Hello from $(hostname)</h1>" > /usr/share/nginx/html/index.html

    # node-exporter lets Prometheus collect metrics from this instance
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    docker run -d --name=node-exporter -p 9100:9100 prom/node-exporter
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "app-instance" }
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name                = "app-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.app_private_a.id, aws_subnet.app_private_b.id]
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "app-instance"
    propagate_at_launch = true
  }
}

# DATABASE  (RDS MySQL)
# Managed MySQL database in the private DB subnets.
# Not publicly accessible — only reachable from within the VPC.


resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.db_private_a.id, aws_subnet.db_private_b.id]
  tags       = { Name = "db-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier             = "main-mysql"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  tags                   = { Name = "main-mysql" }
}


# PRIVATE DNS  (Route 53)
# Internal domain names so services can find each other
# without hardcoding IP addresses.
#   db.deniztech.internal         -> RDS endpoint
#   monitoring.deniztech.internal -> Monitoring server IP


resource "aws_route53_zone" "private" {
  name = "deniztech.internal"

  vpc {
    vpc_id = aws_vpc.main.id
  }
}

resource "aws_route53_record" "db" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db.deniztech.internal"
  type    = "CNAME"
  ttl     = 300
  records = [aws_db_instance.mysql.address]
}


# MONITORING  (Prometheus + Grafana)
# A single EC2 running both tools inside Docker containers.
#   Prometheus (port 9090) – collects metrics
#   Grafana    (port 3000) – displays dashboards


resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-sg"
  description = "Allow Prometheus (9090) and Grafana (3000) from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "monitoring-sg" }
}

resource "aws_iam_role" "monitoring_role" {
  name = "monitoring-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "monitoring_policy" {
  name = "monitoring-server-policy"
  role = aws_iam_role.monitoring_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "tag:GetResources"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "monitoring_profile" {
  name = "monitoring-server-profile"
  role = aws_iam_role.monitoring_role.name
}

resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public_a.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring_profile.name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

#This section provisions the monitoring server. It installs Prometheus and Grafana through Docker, 
#configures Prometheus to discover app instances automatically, 
#and configures Grafana with both Prometheus and CloudWatch so SOAR ECS and Lambda metrics can be visualized centrally.


  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y docker
    systemctl enable docker
    systemctl start docker

    # Prometheus config file
    mkdir -p /etc/prometheus
    cat > /etc/prometheus/prometheus.yml << 'PROM'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "app-nodes"
    ec2_sd_configs:
      - region: "eu-central-1"
        port: 9100
        filters:
          - name: "tag:Name"
            values: ["app-instance"]
          - name: "instance-state-name"
            values: ["running"]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: "$1:9100"
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
PROM

    # Grafana provisioning: Prometheus for infrastructure metrics and CloudWatch for SOAR/ECS/Lambda metrics
    mkdir -p /etc/grafana/provisioning/datasources
    mkdir -p /etc/grafana/provisioning/dashboards
    mkdir -p /etc/grafana/dashboards

    cat > /etc/grafana/provisioning/datasources/datasources.yml << 'GRAFANA_DS'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
  - name: CloudWatch
    type: cloudwatch
    uid: cloudwatch
    access: proxy
    jsonData:
      authType: default
      defaultRegion: eu-central-1
    editable: true
GRAFANA_DS

    cat > /etc/grafana/provisioning/dashboards/dashboards.yml << 'GRAFANA_PROVIDER'
apiVersion: 1

providers:
  - name: Case Study 2
    orgId: 1
    folder: Case Study 2
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
GRAFANA_PROVIDER

    cat > /etc/grafana/dashboards/soar-operations.json << 'GRAFANA_DASH'
{
  "uid": "soar-operations",
  "title": "SOAR Operations",
  "tags": ["case-study-2", "soar"],
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "refresh": "30s",
  "time": { "from": "now-6h", "to": "now" },
  "panels": [
    {
      "type": "timeseries",
      "title": "SOAR Processor CPU",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
      "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
      "targets": [
        {
          "region": "eu-central-1",
          "namespace": "AWS/ECS",
          "metricName": "CPUUtilization",
          "dimensions": { "ClusterName": "soar-cluster", "ServiceName": "soar-processor" },
          "statistic": "Average",
          "period": "60"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "SOAR Processor Memory",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
      "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
      "targets": [
        {
          "region": "eu-central-1",
          "namespace": "AWS/ECS",
          "metricName": "MemoryUtilization",
          "dimensions": { "ClusterName": "soar-cluster", "ServiceName": "soar-processor" },
          "statistic": "Average",
          "period": "60"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "SES Alert Lambda Invocations",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
      "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
      "targets": [
        {
          "region": "eu-central-1",
          "namespace": "AWS/Lambda",
          "metricName": "Invocations",
          "dimensions": { "FunctionName": "soar-ses-alert" },
          "statistic": "Sum",
          "period": "60"
        },
        {
          "region": "eu-central-1",
          "namespace": "AWS/Lambda",
          "metricName": "Errors",
          "dimensions": { "FunctionName": "soar-ses-alert" },
          "statistic": "Sum",
          "period": "60"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "S3 Archive Lambda Invocations",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
      "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
      "targets": [
        {
          "region": "eu-central-1",
          "namespace": "AWS/Lambda",
          "metricName": "Invocations",
          "dimensions": { "FunctionName": "soar-s3-log" },
          "statistic": "Sum",
          "period": "60"
        },
        {
          "region": "eu-central-1",
          "namespace": "AWS/Lambda",
          "metricName": "Errors",
          "dimensions": { "FunctionName": "soar-s3-log" },
          "statistic": "Sum",
          "period": "60"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Application Node Exporter Up",
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 16 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [
        {
          "expr": "up{job=\"app-nodes\"}",
          "legendFormat": "{{instance_id}} {{availability_zone}}",
          "refId": "A"
        }
      ]
    }
  ]
}
GRAFANA_DASH

    # Start Prometheus
    docker run -d \
      --name prometheus \
      --restart always \
      -p 9090:9090 \
      -v /etc/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
      prom/prometheus

    # Start Grafana (default login: admin / admin)
    docker run -d \
      --name grafana \
      --restart always \
      -p 3000:3000 \
      -v /etc/grafana/provisioning:/etc/grafana/provisioning \
      -v /etc/grafana/dashboards:/var/lib/grafana/dashboards \
      grafana/grafana
  EOF
  )

  tags = { Name = "monitoring-server" }
}

resource "aws_route53_record" "monitoring" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "monitoring.deniztech.internal"
  type    = "A"
  ttl     = 300
  records = [aws_instance.monitoring.private_ip]
}


# OUTPUTS
# These values are printed after terraform apply.


output "alb_dns_name" {
  description = "Open this URL in your browser to reach the app"
  value       = aws_lb.app_alb.dns_name
}

output "bastion_public_ip" {
  description = "SSH into this IP to access private resources"
  value       = aws_instance.bastion.public_ip
}

output "monitoring_public_ip" {
  description = "Grafana: http://<ip>:3000  |  Prometheus: http://<ip>:9090"
  value       = aws_instance.monitoring.public_ip
}
