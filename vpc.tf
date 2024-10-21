# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_count     = min(3, length(data.aws_availability_zones.available.names))
  subnet_count = local.az_count * 2 # 2 subnets (1 public, 1 private) per AZ
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
  count                   = var.vpc_count * local.az_count
  vpc_id                  = aws_vpc.main[floor(count.index / local.az_count)].id
  cidr_block              = cidrsubnet(aws_vpc.main[floor(count.index / local.az_count)].cidr_block, 8, count.index % local.az_count)
  availability_zone       = data.aws_availability_zones.available.names[count.index % local.az_count]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${floor(count.index / local.az_count) + 1}-${count.index % local.az_count + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = var.vpc_count * local.az_count
  vpc_id            = aws_vpc.main[floor(count.index / local.az_count)].id
  cidr_block        = cidrsubnet(aws_vpc.main[floor(count.index / local.az_count)].cidr_block, 8, (count.index % local.az_count) + local.az_count)
  availability_zone = data.aws_availability_zones.available.names[count.index % local.az_count]

  tags = {
    Name = "${var.project_name}-private-subnet-${floor(count.index / local.az_count) + 1}-${count.index % local.az_count + 1}"
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
  count          = var.vpc_count * local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[floor(count.index / local.az_count)].id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private" {
  count          = var.vpc_count * local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[floor(count.index / local.az_count)].id
}

resource "aws_security_group" "app_sg" {
  name        = "application-security-group"
  description = "Security group for web application"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "application-security-group"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "database-security-group"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "database-security-group"
  }
}

# RDS Parameter Group
resource "aws_db_parameter_group" "custom_pg" {
  family = "mysql8.0"
  name   = "csye6225-pg"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "csye6225-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "CSYE6225 RDS Subnet Group"
  }
}

# RDS Instance
resource "aws_db_instance" "csye6225" {
  identifier           = "csye6225"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp2"
  db_name              = "csye6225"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = aws_db_parameter_group.custom_pg.name
  skip_final_snapshot  = true
  publicly_accessible  = false
  multi_az             = false

  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
}
resource "aws_instance" "app_instance" {
  ami                    = var.custom_ami_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  depends_on = [aws_db_instance.csye6225]
  disable_api_termination = false

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }
  user_data = base64encode(<<EOF
  #!/bin/bash
  while ! nc -z ${aws_db_instance.csye6225.endpoint} 3306; do
    sleep 10
  done
  echo "DB_HOST=${aws_db_instance.csye6225.endpoint}" >> /opt/app/.env
  echo "DB_USER=${var.db_username}" >> /opt/app/.env
  echo "DB_PASSWORD=${var.db_password}" >> /opt/app/.env
  echo "DB_NAME=csye6225" >> /opt/app/.env
  echo "PORT=${var.app_port}" >> /opt/app/.env
  systemctl restart webapp
  EOF
  )

  tags = {
    Name = "web-application-instance"
  }
}