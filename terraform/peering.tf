# ---------------------------------------------------------------------------
# Task 18 - tools-vpc + VPC peering
# ---------------------------------------------------------------------------
resource "aws_vpc" "tools" {
  cidr_block           = var.tools_vpc_cidr # must not overlap with app-vpc
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-tools-vpc" }
}

resource "aws_subnet" "tools" {
  vpc_id                  = aws_vpc.tools.id
  cidr_block              = cidrsubnet(var.tools_vpc_cidr, 8, 1) # 10.1.1.0/24
  availability_zone       = local.azs["a"]
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-tools-a" }
}

resource "aws_route_table" "tools" {
  vpc_id = aws_vpc.tools.id

  tags = { Name = "${var.project_name}-tools-rt" }
}

resource "aws_route_table_association" "tools" {
  subnet_id      = aws_subnet.tools.id
  route_table_id = aws_route_table.tools.id
}

# ---- The peering connection (both VPCs are in the same account, so auto_accept) ----
resource "aws_vpc_peering_connection" "app_tools" {
  vpc_id      = aws_vpc.app.id
  peer_vpc_id = aws_vpc.tools.id
  auto_accept = true

  tags = { Name = "${var.project_name}-app-tools-peering" }
}

# Routes are needed on BOTH sides.
resource "aws_route" "app_to_tools" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = var.tools_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_tools.id
}

resource "aws_route" "tools_to_app" {
  route_table_id            = aws_route_table.tools.id
  destination_cidr_block    = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_tools.id
}

# ---- Let the tools subnet reach the app servers (Security Group side) ----
resource "aws_vpc_security_group_ingress_rule" "app_http_from_tools" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP from the tools subnet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = aws_subnet.tools.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "app_icmp_from_tools" {
  security_group_id = aws_security_group.app.id
  description       = "Ping from the tools subnet"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = aws_subnet.tools.cidr_block
}

# ---- The tools VPC has no internet either, so it needs its own private endpoints ----
resource "aws_security_group" "tools_endpoint" {
  name        = "${var.project_name}-tools-endpoint-sg"
  description = "Interface endpoints in tools-vpc"
  vpc_id      = aws_vpc.tools.id

  tags = { Name = "${var.project_name}-tools-endpoint-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "tools_endpoint_https" {
  security_group_id = aws_security_group.tools_endpoint.id
  description       = "HTTPS from the tools VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.tools_vpc_cidr
}

resource "aws_vpc_endpoint" "tools_interface" {
  for_each = local.ssm_endpoint_services

  vpc_id              = aws_vpc.tools.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.tools.id]
  security_group_ids  = [aws_security_group.tools_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-tools-${each.key}-endpoint" }
}

# Free S3 gateway endpoint so the monitoring server can install packages.
resource "aws_vpc_endpoint" "tools_s3" {
  vpc_id            = aws_vpc.tools.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.tools.id]

  tags = { Name = "${var.project_name}-tools-s3-endpoint" }
}

# ---- The monitoring server ----
resource "aws_security_group" "tools" {
  name        = "${var.project_name}-tools-sg"
  description = "Monitoring server - no inbound rules at all"
  vpc_id      = aws_vpc.tools.id

  tags = { Name = "${var.project_name}-tools-sg" }
}

resource "aws_vpc_security_group_egress_rule" "tools_to_app_http" {
  security_group_id = aws_security_group.tools.id
  description       = "HTTP to the app VPC (through the peering)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "tools_to_app_icmp" {
  security_group_id = aws_security_group.tools.id
  description       = "Ping to the app VPC"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "tools_to_endpoints" {
  security_group_id            = aws_security_group.tools.id
  description                  = "HTTPS to the SSM endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.tools_endpoint.id
}

resource "aws_vpc_security_group_egress_rule" "tools_to_s3" {
  security_group_id = aws_security_group.tools.id
  description       = "HTTPS to S3 (package repos)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.tools_s3.prefix_list_id
}

resource "aws_instance" "tools" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.tools.id
  vpc_security_group_ids      = [aws_security_group.tools.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name # same SSM role
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  volume_tags = {
    Name    = "${var.project_name}-tools-root"
    Project = local.project_tag
  }

  user_data = <<-EOT
    #!/bin/bash
    for i in 1 2 3 4 5; do
      dnf install -y nmap-ncat && break
      sleep 15
    done
  EOT

  user_data_replace_on_change = true

  depends_on = [
    aws_vpc_endpoint.tools_interface,
    aws_vpc_endpoint.tools_s3,
    aws_vpc_security_group_egress_rule.tools_to_endpoints,
    aws_vpc_security_group_egress_rule.tools_to_s3,
  ]

  tags = { Name = "${var.project_name}-tools-monitor" }
}
