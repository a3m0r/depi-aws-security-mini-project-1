# ---------------------------------------------------------------------------
# Task 7 - VPC endpoints: private access to AWS services (no NAT, no internet)
# ---------------------------------------------------------------------------

# S3 = Gateway endpoint: free, works by adding a route (pl-xxxx prefix list).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.app.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project_name}-s3-endpoint" }
}

# Firewall for the interface endpoints: HTTPS from inside the VPC only.
resource "aws_security_group" "endpoint" {
  name        = "${var.project_name}-endpoint-sg"
  description = "Interface endpoints - HTTPS from inside the VPC"
  vpc_id      = aws_vpc.app.id

  tags = { Name = "${var.project_name}-endpoint-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  security_group_id = aws_security_group.endpoint.id
  description       = "HTTPS from the app VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

# Interface endpoints (paid per hour): one network interface in each private subnet.
# These three are what Session Manager needs.
locals {
  ssm_endpoint_services = toset(["ssm", "ssmmessages", "ec2messages"])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.ssm_endpoint_services

  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-${each.key}-endpoint" }
}
