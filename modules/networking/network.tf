data "aws_vpc" "existing" {
  count = local.creating_new_vpc ? 0 : 1
  id    = var.vpc_id
}

resource "aws_vpc" "new" {
  count                = local.creating_new_vpc ? 1 : 0
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "this" {
  count  = local.creating_new_vpc ? 1 : 0
  vpc_id = aws_vpc.new[0].id
}

resource "aws_eip" "nat" {
  count  = local.creating_new_vpc ? local.nat_gateway_count : 0
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-eip-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.creating_new_vpc ? local.nat_gateway_count : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.this]
  tags          = { Name = "${var.name}-nat-gw-${count.index}" }
}

resource "aws_subnet" "public" {
  count                   = local.creating_new_vpc ? 2 : 0
  vpc_id                  = aws_vpc.new[0].id
  cidr_block              = cidrsubnet(aws_vpc.new[0].cidr_block, 3, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count                   = local.creating_new_vpc ? 2 : 0
  vpc_id                  = aws_vpc.new[0].id
  cidr_block              = cidrsubnet(aws_vpc.new[0].cidr_block, 3, count.index + 2)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = false
}

resource "aws_route_table" "public" {
  count  = local.creating_new_vpc ? 1 : 0
  vpc_id = aws_vpc.new[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }
}

resource "aws_route_table" "private_with_nat" {
  count  = local.creating_new_vpc ? local.nat_gateway_count : 0
  vpc_id = aws_vpc.new[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }
}

resource "aws_route_table" "private_isolated" {
  count  = local.creating_new_vpc && (local.nat_gateway_count == 0) ? 1 : 0
  vpc_id = aws_vpc.new[0].id
  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "public" {
  count          = local.creating_new_vpc ? length(aws_subnet.public) : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  count          = local.creating_new_vpc ? length(aws_subnet.private) : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = local.nat_gateway_count > 0 ? element(aws_route_table.private_with_nat[*].id, count.index) : aws_route_table.private_isolated[0].id
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = local.creating_new_vpc && var.enable_vpc_flow_logs ? 1 : 0
  name_prefix       = "/aws/vpc/${var.name}-flow-logs"
  retention_in_days = 365
}

resource "aws_flow_log" "this" {
  count                    = local.creating_new_vpc && var.enable_vpc_flow_logs ? 1 : 0
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  log_destination_type     = "cloud-watch-logs"
  vpc_id                   = aws_vpc.new[0].id
  iam_role_arn             = aws_iam_role.vpc_flow_logs_role[0].arn
  traffic_type             = "ALL"
  max_aggregation_interval = 60
}

data "aws_subnets" "existing_all" {
  count = local.creating_new_vpc ? 0 : 1
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}
