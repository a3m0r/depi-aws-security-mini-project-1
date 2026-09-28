# ---------------------------------------------------------------------------
# Task 17 - Auto-remediation: Lambda closes an open SSH rule by itself
# Flow: someone opens 22 -> CloudTrail -> EventBridge -> Lambda revokes -> SNS email
# ---------------------------------------------------------------------------
locals {
  lambda_name = "${var.project_name}-remediate-ssh"
}

# Least-privilege role: only what the function really uses.
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "remediation-permissions"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSecurityGroups"
        Effect   = "Allow"
        Action   = ["ec2:DescribeSecurityGroups"]
        Resource = "*"
      },
      {
        Sid      = "RevokeRules"
        Effect   = "Allow"
        Action   = ["ec2:RevokeSecurityGroupIngress"]
        Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/*"
      },
      {
        Sid      = "SendEmail"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# Created by Terraform (not by Lambda) so that "terraform destroy" removes it too.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 14
}

# Zip the Python file. The zip is rebuilt automatically when the code changes.
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/remediate_ssh.py"
  output_path = "${path.module}/build/remediate_ssh.zip"
}

resource "aws_lambda_function" "remediate_ssh" {
  function_name = local.lambda_name
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "remediate_ssh.lambda_handler"
  timeout       = 30

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN   = aws_sns_topic.alerts.arn
      DANGEROUS_PORTS = "22,3389"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
  ]
}

# EventBridge rule: match the CloudTrail record of "someone added an inbound rule".
resource "aws_cloudwatch_event_rule" "sg_ingress" {
  name        = "${var.project_name}-sg-ingress-added"
  description = "Fires when an inbound Security Group rule is added"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["AuthorizeSecurityGroupIngress"]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.sg_ingress.name
  arn  = aws_lambda_function.remediate_ssh.arn
}

# Allow EventBridge (and only this rule) to call the function.
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_ssh.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sg_ingress.arn
}
