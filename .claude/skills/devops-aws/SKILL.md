---
name: devops-aws
description: AWS deployment standards — ECS Fargate, EKS, Lambda, RDS, S3/CloudFront, ECR, ALB, VPC, IAM/OIDC, Secrets Manager, CloudWatch, Terraform, CDK. Use when deploying to or writing infrastructure for AWS.
paths:
  - "**/terraform/**/*.tf"
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/cdk/**/*.ts"
  - "**/cdk/**/*.py"
  - "**/*-task-definition*.json"
  - "**/ecs*.json"
  - "**/appspec.yml"
  - "**/buildspec.yml"
  - "**/.github/workflows/cd-aws*.yml"
  - "**/.github/workflows/*aws*.yml"
---

# AWS Deployment Standards

## Architecture Patterns

### Container Workloads → ECS Fargate (default)
```
Route 53 → CloudFront (CDN + WAF)
              ↓
         ALB (HTTPS, path routing)
              ↓
     ECS Fargate Service (auto-scaling)
         ↓              ↓
  Task Definition    Task Definition
  (app container)   (sidecar: datadog/otel)
              ↓
  RDS Aurora PostgreSQL (private subnet)
  ElastiCache Redis     (private subnet)
```

### Kubernetes Workloads → EKS
Use EKS when: multi-team platform, advanced scheduling, GitOps, or existing Kubernetes expertise.
Use ECS Fargate when: single team, simplicity preferred, AWS-native tooling sufficient.

### Serverless → Lambda
Use Lambda for: async event processing, scheduled jobs, lightweight APIs (< 15 min timeout, < 10k RPS).

---

## Infrastructure as Code (Terraform)

### Repository structure
```
infrastructure/
├── modules/
│   ├── ecs-service/         # Reusable ECS service module
│   ├── rds-postgres/        # RDS PostgreSQL module
│   ├── vpc/                 # VPC with public/private subnets
│   └── ecr/                 # ECR repository module
├── environments/
│   ├── staging/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── production/
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
├── backend.tf               # S3 remote state + DynamoDB locking
└── providers.tf
```

### Remote state (required for team use)
```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "myapp-terraform-state"
    key            = "environments/production/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "myapp-terraform-locks"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.6"
}
```

### VPC (always use private subnets for app + DB)
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.app_name}-${var.environment}"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment == "staging"  # Cost saving in staging
  enable_dns_hostnames   = true
  enable_dns_support     = true
}
```

### ECS Fargate service
```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.app_name}-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = var.app_name
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

    environment = [
      { name = "NODE_ENV",  value = var.environment },
      { name = "PORT",      value = tostring(var.container_port) }
    ]

    secrets = [
      { name = "DATABASE_URL", valueFrom = "${aws_secretsmanager_secret.db_url.arn}" },
      { name = "JWT_SECRET",   valueFrom = "${aws_secretsmanager_secret.jwt.arn}" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.app_name}/${var.environment}"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:${var.container_port}/health/live || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 60
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = "${var.app_name}-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.app_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true    # Auto-rollback on deployment failure
  }

  lifecycle {
    ignore_changes = [task_definition]  # Managed by CI/CD, not Terraform
  }
}
```

---

## Container Registry (ECR)

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "${var.app_name}-${var.environment}"
  image_tag_mutability = "IMMUTABLE"  # Prevent tag overwriting

  image_scanning_configuration {
    scan_on_push = true    # Vulnerability scan on every push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

---

## GitHub Actions — OIDC Authentication (no long-lived credentials)

```hcl
# One-time Terraform setup — create OIDC provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions_deploy" {
  name = "github-actions-deploy-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Attach only necessary permissions (least privilege)
resource "aws_iam_role_policy" "deploy" {
  role = aws_iam_role.github_actions_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = aws_ecs_service.app.id
      }
    ]
  })
}
```

```yaml
# .github/workflows/cd-production.yml
name: Deploy to Production (AWS)

on:
  push:
    tags: ["v*"]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC — no stored secrets)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push image
        run: |
          IMAGE_URI="${{ vars.ECR_REGISTRY }}/${{ vars.ECR_REPOSITORY }}:${{ github.sha }}"
          docker build -t "$IMAGE_URI" .
          docker push "$IMAGE_URI"
          echo "IMAGE_URI=$IMAGE_URI" >> $GITHUB_ENV

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster "${{ vars.ECS_CLUSTER }}" \
            --service "${{ vars.ECS_SERVICE }}" \
            --force-new-deployment

      - name: Wait for deployment
        run: |
          aws ecs wait services-stable \
            --cluster "${{ vars.ECS_CLUSTER }}" \
            --services "${{ vars.ECS_SERVICE }}"
```

---

## Secrets Management (AWS Secrets Manager)

```hcl
resource "aws_secretsmanager_secret" "db_url" {
  name                    = "/${var.app_name}/${var.environment}/database-url"
  recovery_window_in_days = var.environment == "production" ? 30 : 0
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://${var.db_user}:${var.db_password}@${aws_db_instance.main.endpoint}/${var.db_name}"
}
```

**Rules:**
- Use Secrets Manager for sensitive values (DB passwords, API keys, JWT secrets)
- Use Parameter Store (SSM) for non-sensitive config (feature flags, URLs, timeouts)
- Never inject secrets as environment variables in ECS task definition plain text — use `secrets` array with ARN reference
- Rotate secrets automatically: enable Rotation in Secrets Manager for DB credentials

---

## Database (RDS Aurora Serverless v2)

```hcl
resource "aws_rds_cluster" "main" {
  cluster_identifier      = "${var.app_name}-${var.environment}"
  engine                  = "aurora-postgresql"
  engine_version          = "15.4"
  database_name           = var.db_name
  master_username         = var.db_user
  manage_master_user_password = true   # Automatic rotation via Secrets Manager

  serverlessv2_scaling_configuration {
    min_capacity = var.environment == "production" ? 0.5 : 0.5
    max_capacity = var.environment == "production" ? 16  : 4
  }

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period      = var.environment == "production" ? 35 : 7
  preferred_backup_window      = "03:00-04:00"
  deletion_protection          = var.environment == "production"
  skip_final_snapshot          = var.environment != "production"

  enabled_cloudwatch_logs_exports = ["postgresql"]
}
```

---

## Static Frontend (S3 + CloudFront)

```hcl
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.app_name}-frontend-${var.environment}"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    # Long cache for hashed assets; short for index.html
    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  # SPA routing — return index.html for 404/403
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions { geo_restriction { restriction_type = "none" } }
  viewer_certificate { cloudfront_default_certificate = true }
}
```

---

## Monitoring (CloudWatch)

```hcl
# ECS service alarm — rollback if error rate spikes
resource "aws_cloudwatch_metric_alarm" "ecs_error_rate" {
  alarm_name          = "${var.app_name}-${var.environment}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}
```

```yaml
# Application-level structured logging (ships to CloudWatch Logs Insights)
# Use this query to find errors in production:
# fields @timestamp, @message
# | filter level = "error"
# | sort @timestamp desc
# | limit 100
```

---

## Cost Optimization

- Use Fargate Spot for non-critical workloads (staging, batch jobs): up to 70% savings
- Aurora Serverless v2 scales to 0 ACUs when idle (staging environment)
- S3 Intelligent-Tiering for objects > 128KB not accessed frequently
- Reserved instances for production RDS if usage is predictable
- Enable AWS Cost Anomaly Detection with budget alerts

---

## Security Checklist

- [ ] All resources in private subnets; only ALB in public subnet
- [ ] Security groups follow least-privilege (app SG only allows ALB SG; RDS SG only allows app SG)
- [ ] No EC2 key pairs or direct SSH access — use AWS Systems Manager Session Manager
- [ ] ECS tasks use task roles (not execution roles) for application AWS API calls
- [ ] ECR image scanning enabled; block deployment if CRITICAL CVEs found
- [ ] CloudTrail enabled in all regions; logs to S3 with integrity validation
- [ ] AWS Config enabled for compliance drift detection
- [ ] WAF attached to CloudFront and ALB in production
- [ ] Database encryption at rest (enabled by default in RDS) and in transit (force SSL)
