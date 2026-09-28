# ---------------------------------------------------------------------------
# Task 14 - CloudTrail       (who did what, and when)
# Task 15 - VPC Flow Logs    (what crossed the network)
# Task 16 - CloudWatch       (how is it performing) + SNS alerts
# ---------------------------------------------------------------------------
locals {
  trail_name = "${var.project_name}-trail"
  # Built as a string (not a reference) so the bucket policy can name it without a dependency loop.
  trail_arn = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

# ===== SNS topic used by alarms and by the Lambda function ===================
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# The email stays "Pending confirmation" until you click the link AWS sends you.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ===== Task 14 - CloudTrail ==================================================
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/${var.project_name}/cloudtrail"
  retention_in_days = 14
}

resource "aws_iam_role" "cloudtrail_to_cw" {
  name = "${var.project_name}-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_cw" {
  name = "write-to-log-group"
  role = aws_iam_role.cloudtrail_to_cw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true # signed digest files: proves logs were not edited

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cw.arn

  # Selector 1: all management events (console clicks, API calls).
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  # Selector 2: object-level READS on the app bucket (data events).
  event_selector {
    read_write_type           = "ReadOnly"
    include_management_events = false

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.app.arn}/"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_iam_role_policy.cloudtrail_to_cw,
  ]
}

# ===== Task 15 - VPC Flow Logs ================================================
resource "aws_cloudwatch_log_group" "flowlogs" {
  name              = "/depi-sec/vpc/flowlogs"
  retention_in_days = 14
}

resource "aws_iam_role" "flowlogs" {
  name = "${var.project_name}-flowlogs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flowlogs" {
  name = "write-to-log-group"
  role = aws_iam_role.flowlogs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.flowlogs.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups", "logs:DescribeLogStreams"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "app_vpc" {
  vpc_id          = aws_vpc.app.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flowlogs.arn
  iam_role_arn    = aws_iam_role.flowlogs.arn

  depends_on = [aws_iam_role_policy.flowlogs]
}

# ===== Task 16 - CloudWatch alarms ============================================
# Alarm 1: CPU above 70% for 2 periods of 5 minutes (one alarm per server).
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = aws_instance.app

  alarm_name          = "${var.project_name}-cpu-high-${each.key}"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = each.value.id
  }
}

# Alarm 2: at least one unhealthy target behind the load balancer.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}

# Alarm 3: RDS free storage below 2 GB (2 * 1024^3 bytes).
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-rds-low-storage"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}

# Alarm 4 (security): count failed console logins found in the CloudTrail log group.
resource "aws_cloudwatch_log_metric_filter" "failed_console_login" {
  name           = "${var.project_name}-failed-console-login"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = \"ConsoleLogin\") && ($.errorMessage = \"Failed authentication\") }"

  metric_transformation {
    name      = "ConsoleLoginFailures"
    namespace = "DEPI/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "failed_console_login" {
  alarm_name          = "${var.project_name}-failed-console-login"
  namespace           = "DEPI/Security"
  metric_name         = "ConsoleLoginFailures"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# Dashboard with the four metrics.
resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "${var.project_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EC2 CPU (%)"
          region  = var.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 300
          metrics = [for k, i in aws_instance.app : ["AWS/EC2", "CPUUtilization", "InstanceId", i.id]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB unhealthy targets"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS free storage (bytes)"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.main.identifier]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Failed console logins"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["DEPI/Security", "ConsoleLoginFailures"]
          ]
        }
      }
    ]
  })
}
