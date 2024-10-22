# Outputs
output "vpc_ids" {
  description = "IDs of the created VPCs"
  value       = aws_vpc.main[*].id
}

output "public_subnet_ids" {
  description = "IDs of the created public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the created private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_ids" {
  description = "IDs of the created Internet Gateways"
  value       = aws_internet_gateway.main[*].id
}

output "public_route_table_ids" {
  description = "IDs of the public route tables"
  value       = aws_route_table.public[*].id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = aws_route_table.private[*].id
}

output "ec2_public_ip" {
  value = aws_instance.app_instance.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.csye6225.endpoint
}