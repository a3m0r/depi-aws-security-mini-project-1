output "cloudfront_url" {
  description = "Open this in a browser: the public HTTPS front door."
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "alb_dns_name" {
  description = "Direct ALB address. Must answer 403 (locked mode)."
  value       = aws_lb.main.dns_name
}

output "app_instance_ids" {
  description = "Use these in Console -> EC2 -> Connect -> Session Manager."
  value       = { for k, i in aws_instance.app : k => i.id }
}

output "app_private_ips" {
  description = "Private IPs of the app servers (for the peering curl test)."
  value       = { for k, i in aws_instance.app : k => i.private_ip }
}

output "tools_instance_id" {
  description = "Monitoring server in tools-vpc (Session Manager)."
  value       = aws_instance.tools.id
}

output "rds_endpoint" {
  description = "Database address (only reachable from the app servers)."
  value       = aws_db_instance.main.address
}

output "db_secret_name" {
  description = "Secrets Manager secret that holds the database password."
  value       = aws_secretsmanager_secret.db.name
}

output "app_bucket" {
  value = aws_s3_bucket.app.id
}

output "logs_bucket" {
  value = aws_s3_bucket.logs.id
}

output "app_security_group_id" {
  description = "Use it for the Task 17 test (add SSH 0.0.0.0/0 to this group)."
  value       = aws_security_group.app.id
}

output "efs_arn" {
  description = "Resource ARN for the on-demand backup test (Task 19)."
  value       = aws_efs_file_system.shared.arn
}

output "backup_role_arn" {
  description = "Role ARN for the on-demand backup test (Task 19)."
  value       = aws_iam_role.backup.arn
}

output "dev1_initial_password" {
  description = "One-time console password of depi-dev-1 (must be changed at first login)."
  value       = aws_iam_user_login_profile.dev1.password
  sensitive   = true
}
