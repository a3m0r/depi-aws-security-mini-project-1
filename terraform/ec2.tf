# ---------------------------------------------------------------------------
# Task 8 + 9 - Private web servers: instance role, Session Manager, encrypted disks
# ---------------------------------------------------------------------------

# Always find the newest Amazon Linux 2023 image - never hard-code an AMI ID.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  app_servers = {
    a = {
      name      = "server-a"
      az        = local.azs["a"]
      subnet_id = aws_subnet.private["a"].id
    }
    b = {
      name      = "server-b"
      az        = local.azs["b"]
      subnet_id = aws_subnet.private["b"].id
    }
  }
}

resource "aws_instance" "app" {
  for_each = local.app_servers

  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  associate_public_ip_address = false
  # key_name is intentionally NOT set: no SSH key, no port 22. Access = Session Manager.

  # IMDSv2 only (blocks a common credential-theft trick).
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  # default_tags do not reach the root volume, and AWS Backup finds EBS volumes by this tag.
  volume_tags = {
    Name    = "${var.project_name}-${each.value.name}-root"
    Project = local.project_tag
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    server_name     = each.value.name
    az              = each.value.az
    efs_id          = aws_efs_file_system.shared.id
    access_point_id = aws_efs_access_point.app.id
  })
  user_data_replace_on_change = true

  # The server needs these to exist BEFORE it boots (packages, SSM registration, EFS, NACL).
  depends_on = [
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.interface,
    aws_efs_mount_target.private,
    aws_network_acl.private,
    aws_vpc_security_group_egress_rule.app_to_s3,
    aws_vpc_security_group_egress_rule.app_to_endpoints,
    aws_vpc_security_group_egress_rule.app_to_efs,
  ]

  tags = { Name = "${var.project_name}-${each.value.name}" }
}
