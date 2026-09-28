# ---------------------------------------------------------------------------
# Task 19 - AWS Backup: daily backups in a vault with a GOVERNANCE lock
# ---------------------------------------------------------------------------
resource "aws_backup_vault" "main" {
  name = "${var.project_name}-vault"

  # Lab only: lets "terraform destroy" delete old recovery points with the vault.
  force_destroy = true
}

resource "aws_iam_role" "backup" {
  name = "${var.project_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "daily" {
  name = "${var.project_name}-daily"

  rule {
    rule_name         = "daily-0500-utc"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 * * ? *)" # every day at 05:00 UTC
    start_window      = 60                  # minutes
    completion_window = 180                 # minutes

    lifecycle {
      delete_after = 30 # keep 30 days
    }
  }
}

# Pick resources by tag: everything tagged Project = depi-mini-project-1
# (EBS volumes, the EFS file system and the RDS database all carry that tag).
resource "aws_backup_selection" "by_tag" {
  name         = "${var.project_name}-by-tag"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.daily.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Project"
    value = local.project_tag
  }

  depends_on = [
    aws_iam_role_policy_attachment.backup,
    aws_iam_role_policy_attachment.restore,
  ]
}

# ---------------------------------------------------------------------------
# !!! IMPORTANT - GOVERNANCE MODE !!!
# In AWS Backup, setting "changeable_for_days" turns the lock into COMPLIANCE mode:
# after that many days (minimum 3) the lock becomes permanent and NOBODY can remove it,
# not even AWS Support. The project sheet asks for governance mode AND for
# changeable_for_days = 3 - those two contradict each other.
# We keep the goal (governance mode) and leave changeable_for_days out on purpose.
# ---------------------------------------------------------------------------
resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name  = aws_backup_vault.main.name
  min_retention_days = 7
  max_retention_days = 365
  # changeable_for_days = 3   <-- NEVER add this line (it means compliance mode)
}
