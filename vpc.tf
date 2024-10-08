# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  count      = var.vpc_count
  cidr_block = cidrsubnet(var.base_cidr_block, 0, count.index)

  tags = {
    Name = "${var.project_name}-vpc-${count.index + 1}"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = var.vpc_count * var.subnet_count
  vpc_id                  = aws_vpc.main[floor(count.index / var.subnet_count)].id
  cidr_block              = cidrsubnet(aws_vpc.main[floor(count.index / var.subnet_count)].cidr_block, 8, count.index % var.subnet_count)
  availability_zone       = data.aws_availability_zones.available.names[count.index % var.subnet_count]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${floor(count.index / var.subnet_count) + 1}-${count.index % var.subnet_count + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = var.vpc_count * var.subnet_count
  vpc_id            = aws_vpc.main[floor(count.index / var.subnet_count)].id
  cidr_block        = cidrsubnet(aws_vpc.main[floor(count.index / var.subnet_count)].cidr_block, 8, (count.index % var.subnet_count) + var.subnet_count)
  availability_zone = data.aws_availability_zones.available.names[count.index % var.subnet_count]

  tags = {
    Name = "${var.project_name}-private-subnet-${floor(count.index / var.subnet_count) + 1}-${count.index % var.subnet_count + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  count  = var.vpc_count
  vpc_id = aws_vpc.main[count.index].id

  tags = {
    Name = "${var.project_name}-igw-${count.index + 1}"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  count  = var.vpc_count
  vpc_id = aws_vpc.main[count.index].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project_name}-public-rt-${count.index + 1}"
  }
}

# Private Route Table
resource "aws_route_table" "private" {
  count  = var.vpc_count
  vpc_id = aws_vpc.main[count.index].id

  tags = {
    Name = "${var.project_name}-private-rt-${count.index + 1}"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public" {
  count          = var.vpc_count * var.subnet_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[floor(count.index / var.subnet_count)].id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private" {
  count          = var.vpc_count * var.subnet_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[floor(count.index / var.subnet_count)].id
}