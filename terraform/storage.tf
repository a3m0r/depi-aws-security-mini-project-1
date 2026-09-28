# ---------------------------------------------------------------------------
# Task 9 - EFS shared file system
# Task 10 - S3 buckets that cannot leak
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# ===== EFS ===================================================================
resource "aws_efs_file_system" "shared" {
  creation_token = "${var.project_name}-efs"
  encrypted      = true

  tags = { Name = "${var.project_name}-efs" }
}

# One mount target (a network door) in each private subnet.
resource "aws_efs_mount_target" "private" {
  for_each = aws_subnet.private

  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs.id]
}

# The access point forces every client to act as user 1000 inside /app-data.
resource "aws_efs_access_point" "app" {
  file_system_id = aws_efs_file_system.shared.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/app-data"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = { Name = "${var.project_name}-efs-ap" }
}

# ===== S3 ====================================================================
# Bucket names are global, so add a random suffix.
resource "random_id" "suffix" {
  byte_length = 4
}

# force_destroy = true lets "terraform destroy" empty the bucket (including old
# versions) by itself. Fine for a lab, never for production data.
resource "aws_s3_bucket" "app" {
  bucket        = "${var.project_name}-app-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket" "logs" {
  bucket        = "${var.project_name}-logs-${random_id.suffix.hex}"
  force_destroy = true
}

locals {
  # Settings that must be identical on both buckets are written once and looped.
  buckets = {
    app  = aws_s3_bucket.app.id
    logs = aws_s3_bucket.logs.id
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.buckets

  bucket = each.value

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  bucket = each.value

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = local.buckets

  bucket = each.value

  rule {
    id     = "old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# CloudFront writes its access logs with ACLs, so the logs bucket must allow them.
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# ---- Bucket policies ---------------------------------------------------------
resource "aws_s3_bucket_policy" "app" {
  bucket = aws_s3_bucket.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.app.arn, "${aws_s3_bucket.app.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# The logs bucket policy has two jobs: deny HTTP (Task 10) and let CloudTrail write (Task 14).
# A bucket can have only ONE policy, so both live in this single resource.
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
        }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# A sample file, so you can test "make this object public" (it must be refused).
resource "aws_s3_object" "welcome" {
  bucket       = aws_s3_bucket.app.id
  key          = "welcome.txt"
  content      = "Private file from the depi-sec platform.\n"
  content_type = "text/plain"

  depends_on = [aws_s3_bucket_policy.app]
}
