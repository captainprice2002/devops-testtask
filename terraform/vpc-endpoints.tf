locals {
  interface_vpc_endpoints = toset([
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "elasticloadbalancing",
    "logs",
    "sts",
  ])
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-vpc-endpoints"
  description = "Allow private subnet workloads to reach interface VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from private subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.private_subnets
  }

  tags = {
    Name = "${var.project}-vpc-endpoints"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_vpc_endpoints

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${var.project}-${replace(each.key, ".", "-")}"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name = "${var.project}-s3"
  }
}
