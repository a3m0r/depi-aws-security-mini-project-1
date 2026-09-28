# ---------------------------------------------------------------------------
# Task 5 - Security Groups (tiered firewall)
# Chain:  Internet -> alb-sg -> app-sg -> db-sg / efs-sg
# One resource per rule (aws_vpc_security_group_*_rule), no inline rules.
# NOTE: Terraform removes AWS's default "allow all outbound" rule, so every
#       outbound path a tier needs is written explicitly below.
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Load balancer - the only group open to the internet"
  vpc_id      = aws_vpc.app.id

  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "App servers - reachable only from the load balancer"
  vpc_id      = aws_vpc.app.id

  tags = { Name = "${var.project_name}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "RDS - reachable only from the app servers"
  vpc_id      = aws_vpc.app.id

  tags = { Name = "${var.project_name}-db-sg" }
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "EFS - reachable only from the app servers"
  vpc_id      = aws_vpc.app.id

  tags = { Name = "${var.project_name}-efs-sg" }
}

# ---- ALB -------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to app servers"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.app.id
}

# ---- App servers -----------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "app_http_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP from the ALB security group"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTPS to the SSM interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoint.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_s3" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to S3 through the gateway endpoint (package repos)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}

resource "aws_vpc_security_group_egress_rule" "app_to_efs" {
  security_group_id            = aws_security_group.app.id
  description                  = "NFS to EFS"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.efs.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "MySQL to RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.db.id
}

# ---- Database and file system ---------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from app servers only"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_app" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS from app servers only"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.app.id
}

# NOTE: no group has an inbound rule for port 22 - on purpose.

# ---------------------------------------------------------------------------
# Task 6 - Network ACL for the private subnets (stateless second layer)
#
# Rules are read from the lowest number to the highest. First match wins.
#
# Two additions compared with the project sheet (both explained in docs/):
#  * Rule 120 allows return traffic from 0.0.0.0/0, not only from 10.0.0.0/16.
#    Reason: packages come from S3 (public S3 IPs, through the gateway endpoint).
#    The reply comes FROM an S3 address, so a 10.0.0.0/16-only rule would drop it.
#  * Rules 130/140 (in) and 120/130 (out) allow the tools VPC (Task 18), because
#    a NACL is stateless and would otherwise block the peering traffic.
# ---------------------------------------------------------------------------
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.app.id
  subnet_ids = [for s in aws_subnet.private : s.id]

  # --- inbound ---
  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = var.vpc_cidr
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    cidr_block = var.vpc_cidr
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 120
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  ingress {
    rule_no    = 130
    action     = "allow"
    protocol   = "tcp"
    cidr_block = var.tools_vpc_cidr
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 140
    action     = "allow"
    protocol   = "icmp"
    cidr_block = var.tools_vpc_cidr
    from_port  = 0
    to_port    = 0
    icmp_type  = -1
    icmp_code  = -1
  }

  ingress {
    rule_no    = 200
    action     = "deny"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  # --- outbound ---
  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    rule_no    = 120
    action     = "allow"
    protocol   = "tcp"
    cidr_block = var.tools_vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 130
    action     = "allow"
    protocol   = "icmp"
    cidr_block = var.tools_vpc_cidr
    from_port  = 0
    to_port    = 0
    icmp_type  = -1
    icmp_code  = -1
  }

  tags = { Name = "${var.project_name}-private-nacl" }
}
