# ---------------------------------------------------------------------------
# Task 3 - Identity: users, groups, roles, least privilege
# ---------------------------------------------------------------------------

# Account password policy (applies to the whole AWS account).
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  max_password_age               = 90
  allow_users_to_change_password = true
}

# Group -> the developers get read-only access to the console.
resource "aws_iam_group" "developers" {
  name = "${var.project_name}-developers"
}

resource "aws_iam_group_policy_attachment" "developers_readonly" {
  group      = aws_iam_group.developers.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# User -> gets permissions ONLY through the group (zero direct policies).
resource "aws_iam_user" "dev1" {
  name          = "depi-dev-1"
  force_destroy = true
}

resource "aws_iam_user_group_membership" "dev1" {
  user   = aws_iam_user.dev1.name
  groups = [aws_iam_group.developers.name]
}

resource "aws_iam_user_login_profile" "dev1" {
  user                    = aws_iam_user.dev1.name
  password_reset_required = true
  password_length         = 24

  depends_on = [aws_iam_account_password_policy.strict]
}

# Custom policy: read objects from ONE bucket, nothing else.
resource "aws_iam_policy" "s3_app_read" {
  name        = "${var.project_name}-s3-app-read"
  description = "s3:GetObject on the app bucket only."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadAppBucketObjects"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.app.arn}/*"
    }]
  })
}

# Role for the EC2 servers (no access keys anywhere).
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_s3_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.s3_app_read.arn
}

# EC2 cannot use a role directly - it needs an "instance profile" wrapper.
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}
