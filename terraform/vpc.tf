# ---------------------------------------------------------------------------
# Task 4 - VPC, subnets, routing
# ---------------------------------------------------------------------------
locals {
  # Two Availability Zones (fixed by the project rules).
  azs = {
    a = "${var.region}a"
    b = "${var.region}b"
  }

  # cidrsubnet(10.0.0.0/16, 8, 1) = 10.0.1.0/24 ... matches the README table.
  public_subnets = {
    a = cidrsubnet(var.vpc_cidr, 8, 1) # 10.0.1.0/24
    b = cidrsubnet(var.vpc_cidr, 8, 2) # 10.0.2.0/24
  }
  private_subnets = {
    a = cidrsubnet(var.vpc_cidr, 8, 11) # 10.0.11.0/24
    b = cidrsubnet(var.vpc_cidr, 8, 12) # 10.0.12.0/24
  }
}

resource "aws_vpc" "app" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-app-vpc" }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.app.id
  cidr_block              = each.value
  availability_zone       = local.azs[each.key]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.app.id
  cidr_block              = each.value
  availability_zone       = local.azs[each.key]
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-private-${each.key}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.app.id

  tags = { Name = "${var.project_name}-igw" }
}

# PUBLIC route table: has a route to the Internet Gateway. That is what makes a subnet public.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# PRIVATE route table: NO internet route. Only the automatic "local" route exists.
# (Routes for the S3 endpoint and for VPC peering are added later as separate resources.)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.app.id

  tags = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
