# Output for VPC ID
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main[0].id
}

# Output for Public Subnets
output "public_subnets" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

# Output for Private Subnets
output "private_subnets" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

# Output for Load Balancer DNS Name
output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.app_lb.dns_name
}

# Output for Auto Scaling Group Name
output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app_asg.name
}

# Output for S3 Bucket Name
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.app_bucket.bucket
}

# Output for Route53 Record (DNS)
output "route53_record" {
  description = "The Route53 DNS record pointing to Load Balancer"
  value       = aws_route53_record.app_dns.name
}