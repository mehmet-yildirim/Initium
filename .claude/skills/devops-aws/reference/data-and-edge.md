# Aurora, secrets, S3 and CloudFront recipes

Terraform AWS provider `~> 6.0`.

## Aurora PostgreSQL serverless (scale to zero outside production)

```hcl
locals {
  is_production = var.environment == "production"
}

resource "aws_rds_cluster" "main" {
  cluster_identifier = "${var.app_name}-${var.environment}"
  engine             = "aurora-postgresql"
  engine_version     = "17.10"
  database_name      = var.db_name
  master_username    = "dbadmin"

  # RDS generates the password, stores it in Secrets Manager and rotates it.
  # Nothing secret enters Terraform state.
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.data.arn
  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.rds.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  serverlessv2_scaling_configuration {
    min_capacity             = local.is_production ? 1 : 0
    max_capacity             = local.is_production ? 32 : 4
    seconds_until_auto_pause = local.is_production ? null : 900
  }

  backup_retention_period         = local.is_production ? 35 : 7
  preferred_backup_window         = "02:00-03:00"
  deletion_protection             = local.is_production
  skip_final_snapshot             = !local.is_production
  final_snapshot_identifier       = local.is_production ? "${var.app_name}-final" : null
  enabled_cloudwatch_logs_exports = ["postgresql"]
}

resource "aws_rds_cluster_instance" "main" {
  count                        = local.is_production ? 2 : 1
  identifier                   = "${var.app_name}-${var.environment}-${count.index}"
  cluster_identifier           = aws_rds_cluster.main.id
  engine                       = aws_rds_cluster.main.engine
  engine_version               = aws_rds_cluster.main.engine_version
  instance_class               = "db.serverless"
  performance_insights_enabled = true
}

resource "aws_rds_cluster_parameter_group" "main" {
  name   = "${var.app_name}-${var.environment}-pg17"
  family = "aurora-postgresql17"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}
```

- `seconds_until_auto_pause` is only valid with `min_capacity = 0` (300–86400 s). A minimum of
  0.5 or more disables auto-pause.
- Resuming takes seconds; clients need connect timeouts and retries.
- The application connects with IAM auth (`rds-db:connect` on the task role, short-lived token
  via the SDK signer) or with an app-specific user whose secret has Secrets Manager rotation.
  The master secret (`aws_rds_cluster.main.master_user_secret[0].secret_arn`) is for migrations
  and break-glass only.
- Major upgrades: create a blue/green deployment (`aws rds create-blue-green-deployment`) and
  switch over after validation.

## Secrets Manager

Terraform creates the secret container; values come from rotation or an out-of-band process.

```hcl
resource "aws_secretsmanager_secret" "jwt" {
  name                    = "/${var.app_name}/${var.environment}/jwt-signing-key"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = var.environment == "production" ? 30 : 7
}
```

If Terraform must set a value, use the write-only argument (`secret_string_wo` with
`secret_string_wo_version`, Terraform ≥ 1.11) so it is never persisted in state.

## Private S3 bucket + CloudFront with OAC

```hcl
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.app_name}-frontend-${var.environment}"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.app_name}-${var.environment}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  web_acl_id          = var.waf_web_acl_arn

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-frontend"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn # must be issued in us-east-1
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2025"
  }
}

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json
}
```

- Without `s3:ListBucket`, a missing key returns 403 from S3 — the SPA fallback above maps it to
  `index.html`.
- Upload hashed assets with `Cache-Control: public, max-age=31536000, immutable` and `index.html`
  with `no-cache`; invalidate only `/index.html` on deploy.
