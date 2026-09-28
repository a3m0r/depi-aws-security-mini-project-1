# ---------------------------------------------------------------------------
# Task 2 - Cost governance as a security control
# ---------------------------------------------------------------------------

# 1) A policy that blocks the two most expensive "create" actions.
resource "aws_iam_policy" "deny_expensive" {
  name        = "${var.project_name}-deny-expensive"
  description = "Denies launching EC2 and RDS. Attached automatically by the budget action."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyExpensiveCreates"
      Effect   = "Deny"
      Action   = ["ec2:RunInstances", "rds:CreateDBInstance"]
      Resource = "*"
    }]
  })
}

# 2) A role that the AWS Budgets service can assume to attach that policy.
resource "aws_iam_role" "budget_action" {
  name = "${var.project_name}-budget-action-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# The role may only attach/detach policies on the developers group.
resource "aws_iam_role_policy" "budget_action" {
  name = "attach-deny-policy-to-developers"
  role = aws_iam_role.budget_action.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:AttachGroupPolicy", "iam:DetachGroupPolicy"]
      Resource = aws_iam_group.developers.arn
    }]
  })
}

# 3) The monthly budget: $10, two email notifications.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# 4) The ACTION: at 90% of actual cost, attach the deny policy automatically.
resource "aws_budgets_budget_action" "deny_at_90" {
  budget_name        = aws_budgets_budget.monthly.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budget_action.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 90
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.deny_expensive.arn
      groups     = [aws_iam_group.developers.name]
    }
  }

  subscriber {
    subscription_type = "EMAIL"
    address           = var.alert_email
  }

  depends_on = [aws_iam_role_policy.budget_action]
}
