# ---------------------------------------------------------------------------
# Task 11 - Private RDS MySQL database
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = [for s in aws_subnet.private : s.id]

  tags = { Name = "${var.project_name}-db-subnets" }
}

# The password is generated, never typed. These characters are allowed by RDS.
resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!#%^*()-_=+[]{}<>?"
}

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-mysql"

  engine         = "mysql"
  engine_version = "8.4" # MySQL 8.0 left RDS standard support on 2026-07-31 (paid Extended Support).
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "dbadmin"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 1

  # Lab settings: we MUST be able to destroy it.
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = { Name = "${var.project_name}-mysql" }
}

# Store the credentials in Secrets Manager instead of writing them anywhere in the code.
# recovery_window_in_days = 0 -> deleted immediately, so destroy + apply again does not clash.
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project_name}-db-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = 3306
    dbname   = aws_db_instance.main.db_name
  })
}
