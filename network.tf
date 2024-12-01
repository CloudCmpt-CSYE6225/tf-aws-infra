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

  # Add a route to direct all outbound traffic to the NAT Gateway
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id # Reference to NAT Gateway 
  }

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
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  # ingress {
  #   from_port       = 80
  #   to_port         = 80
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.lb_sg.id]
  # }

  # ingress {
  #   from_port       = 443
  #   to_port         = 443
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.lb_sg.id]
  # }

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
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
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [
      aws_security_group.app_sg.id,
      aws_security_group.lambda_sg.id
    ]
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

#Load Balancer security group
resource "aws_security_group" "lb_sg" {
  name        = "load-balancer-security-group"
  description = "Security group for load balancer"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "load-balancer-security-group"
  }
}

resource "random_uuid" "bucket_name" {
}

resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 10

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "key-for-s3",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      }
      # {
      #   Sid    = "Allow S3 Service to Use the Key",
      #   Effect = "Allow",
      #   Principal = {
      #     AWS = [
      #       "arn:aws:iam::aws:service-role/s3.amazonaws.com/AWSServiceRoleForS3" // Example S3 service role
      #     ]
      #   },
      #   Action = [
      #     "kms:Encrypt",
      #     "kms:Decrypt",
      #     "kms:ReEncrypt*",
      #     "kms:GenerateDataKey*",
      #     "kms:DescribeKey"
      #   ],
      #   Resource = "*"
      # },
      # {
      #   Sid    = "Allow Management of Grants",
      #   Effect = "Allow",
      #   Principal = {
      #     AWS = [
      #       "arn:aws:iam::aws:service-role/s3.amazonaws.com/AWSServiceRoleForS3" // Example S3 service role
      #     ]
      #   },
      #   Action = [
      #     "kms:CreateGrant",
      #     "kms:ListGrants",
      #     "kms:RevokeGrant"
      #   ],
      #   Resource = "*",
      #   Condition = {
      #     Bool : {
      #       "kms:GrantIsForAWSResource" : true
      #     }
      #   }
      # }
    ]
  })
}


# S3 Bucket Configuration
resource "aws_s3_bucket" "app_bucket" {
  bucket        = random_uuid.bucket_name.result
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  bucket = aws_s3_bucket.app_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.app_bucket.bucket

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# Update the existing IAM role with S3 permissions
resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3_access_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "kms:Ecrypt",
          "kms:Decrypt",
          "kms:CreateGrant",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_s3_bucket.app_bucket.arn,
          "${aws_s3_bucket.app_bucket.arn}/*"
        ]
      }
    ]
  })
}

# # Route 53 Configuration
# resource "aws_route53_record" "app_dns" {
#   zone_id = var.route53_zone_id
#   name    = var.environment == "dev" ? "dev.${var.domain_name}" : "demo.${var.domain_name}"
#   type    = "A"
#   ttl     = 300
#   records = [aws_instance.app_instance.public_ip]
# }


resource "aws_route53_record" "sendgrid_dkim" {
  zone_id = var.route53_zone_id
  name    = "s1._domainkey"
  type    = "CNAME"
  ttl     = "300"
  records = ["s1.domainkey.${var.domain_name}.sendgrid.net."]
}

resource "aws_route53_record" "sendgrid_spf" {
  zone_id = var.route53_zone_id
  name    = ""
  type    = "TXT"
  ttl     = "300"
  records = ["v=spf1 include:sendgrid.net ~all"]
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

resource "aws_kms_key" "rds_key" {
  description             = "KMS key for RDS"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 10

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "key-for-rds",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow access for Key Administrators",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS"
        },
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow attachment of persistent resources",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS"
        },
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource = "*",
        Condition = {
          Bool : {
            "kms:GrantIsForAWSResource" : true
          }
        }
      }
    ]
  })
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
  password             = local.db_password_json["DB_PASS"]
  parameter_group_name = aws_db_parameter_group.custom_pg.name
  skip_final_snapshot  = true
  publicly_accessible  = false
  multi_az             = false

  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_key.arn
}

resource "aws_iam_policy" "ec2_policy" {
  name        = "ec2_policy"
  description = "A policy that grants EC2 instances permissions for KMS and Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:CreateGrant"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue",
        "secretmanager:UpdateSecret"]
        Resource = "*"
      }
    ]
  })
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_role_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

# CloudWatch IAM Policy
resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "cloudwatch_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app_log_group" {
  name              = "/webapp/logs"
  retention_in_days = 7
}


resource "aws_iam_role_policy_attachment" "ec2_role_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}

# # EC2 Instance
# resource "aws_instance" "app_instance" {
#   ami                     = var.custom_ami_id
#   instance_type           = "t2.micro"
#   subnet_id               = aws_subnet.public[0].id
#   vpc_security_group_ids  = [aws_security_group.app_sg.id]
#   depends_on              = [aws_db_instance.csye6225]
#   disable_api_termination = false
#   iam_instance_profile    = aws_iam_instance_profile.ec2_profile.name

#   root_block_device {
#     volume_size           = 25
#     volume_type           = "gp2"
#     delete_on_termination = true
#   }

#   user_data = base64encode(templatefile("${path.module}/user_data.sh", {
#     db_host                  = aws_db_instance.csye6225.address
#     db_username              = var.db_username
#     db_password              = var.db_password
#     db_name                  = aws_db_instance.csye6225.db_name
#     app_port                 = var.app_port
#     s3_bucket                = aws_s3_bucket.app_bucket.bucket
#     region                   = var.region
#     sendgrid_api_key         = var.sendgrid_api_key
#     domain_name              = var.domain_name
#     sendgrid_verified_sender = var.sendgrid_verified_sender
#   }))

#   tags = {
#     Name = "web-application-instance"
#   }
# }

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  name                = "webapp-asg"
  desired_capacity    = var.desired_capacity
  max_size            = var.max_capacity
  min_size            = var.min_capacity
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  vpc_zone_identifier = aws_subnet.public[*].id
  default_cooldown    = var.cooldown

  launch_template {
    id      = aws_launch_template.app_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "webapp-asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up-policy"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = var.scale_up_adjustment
  cooldown               = var.cooldown
}

resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "scale-up-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = var.scale_up_threshold
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down-policy"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = var.scale_down_adjustment
  cooldown               = var.cooldown
}

resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "scale-down-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = var.scale_down_threshold
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "webapp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "webapp-alb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "webapp-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main[0].id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 120
    timeout             = 5
    path                = "/healthz"
    port                = var.app_port
    unhealthy_threshold = 2
  }
}

# resource "aws_lb_listener" "front_end" {
#   load_balancer_arn = aws_lb.app_lb.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app_tg.arn
#   }
# }

data "aws_acm_certificate" "cert" {
  domain      = "${var.environment}.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "443"
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-2016-08"
  certificate_arn = data.aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Update Route53 to point to ALB
resource "aws_route53_record" "app_dns" {
  zone_id = var.route53_zone_id
  name    = var.environment == "dev" ? "dev.${var.domain_name}" : "demo.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}

#elastic ip for nat gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# NAT Gateway in public subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id # Ensure this is a public subnet
}

resource "aws_sns_topic" "my_topic" {
  name = "my-sns-topic"
}

# Security group for Lambda function
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-security-group"
  description = "Security group for Lambda function"
  vpc_id      = aws_vpc.main[0].id

  # Allow outbound traffic from Lambda to connect to RDS on port 3306 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound traffic 
  }

  tags = {
    Name = "lambda-security-group"
  }
}

resource "aws_lambda_function" "my_lambda_function" {
  filename      = var.file_path
  function_name = "my_lambda_function"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30

  environment {
    variables = {
      DB_HOST = aws_db_instance.csye6225.address
      DB_USER = var.db_username
      # DB_PASS                  = var.db_password
      DB_DATABASE = aws_db_instance.csye6225.db_name
      # SENDGRID_API_KEY         = var.sendgrid_api_key
      # SENDGRID_VERIFIED_SENDER = var.sendgrid_verified_sender
      SNS_TOPIC_ARN = aws_sns_topic.my_topic.arn
      REGION        = var.region
      environment   = var.environment
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id          # Private subnets where RDS is located
    security_group_ids = [aws_security_group.lambda_sg.id] # Security group for Lambda function
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_sns_topic.my_topic
  ]
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.my_lambda_function.function_name}"
  retention_in_days = 5 # retention period
}

resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda_function.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.my_topic.arn
}

resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.my_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.my_lambda_function.arn
}
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy"
  description = "IAM policy for Lambda execution"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "secretsmanager:GetSecretValue"

        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "sns:Publish",
          "sns:Subscribe",
          "sns:Receive"
        ],
        Effect   = "Allow",
        Resource = aws_sns_topic.my_topic.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# New policy attachment for AWSLambdaVPCAccessExecutionRole
resource "aws_iam_role_policy_attachment" "lambda_vpc_access_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_kms_key" "ec2_key" {
  description             = "KMS key for EC2"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 10

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "key-default-1",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow EC2 and Related Services to Use the Key",
        Effect = "Allow",
        Principal = {
          AWS = [
            "arn:aws:iam::${var.account_id}:role/ec2_role",
            "arn:aws:iam::${var.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling" // Example Auto Scaling role
          ]
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow EC2 to Create and Manage Grants",
        Effect = "Allow",
        Principal = {
          AWS = [
            "arn:aws:iam::${var.account_id}:role/ec2_role",
            "arn:aws:iam::${var.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling" // Example Auto Scaling role
          ]
        },
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource = "*",
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" : true
          }
        }
      }
    ]
  })
}


# Launch Template
resource "aws_launch_template" "app_template" {
  name = "csye6225_asg"

  image_id      = var.custom_ami_id
  instance_type = "t2.micro"
  key_name      = "AWS"

  block_device_mappings {
    device_name = "/dev/sda1" // Root device
    ebs {
      delete_on_termination = true
      volume_size           = 50
      volume_type           = "gp2"
      encrypted             = true
      kms_key_id            = aws_kms_key.ec2_key.arn // Using the EC2 KMS key for encryption
    }
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_sg.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host                  = aws_db_instance.csye6225.address
    db_username              = var.db_username
    db_password              = var.db_password
    db_name                  = aws_db_instance.csye6225.db_name
    app_port                 = var.app_port
    s3_bucket                = aws_s3_bucket.app_bucket.bucket
    region                   = var.region
    sendgrid_api_key         = var.sendgrid_api_key
    domain_name              = var.domain_name
    sendgrid_verified_sender = var.sendgrid_verified_sender
    sns_topic_arn            = aws_sns_topic.my_topic.arn
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "webapp-asg-instance"
    }
  }
}
resource "aws_iam_policy" "secrets_access_policy" {
  name        = "SecretsAccessPolicy"
  description = "Policy to allow read access to specific secrets in AWS Secrets Manager"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ],
        "Resource" : [
          aws_secretsmanager_secret.sendgrid_credentials.arn,
          aws_secretsmanager_secret.db_password_secret.arn // Add other specific secret ARNs as needed
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : "secretsmanager:ListSecrets",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_kms_key" "secrets_manager_key" {
  description             = "KMS key for Secrets Manager"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 10

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "key-for-secrets-manager",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      }
      # {
      #   Sid    = "Allow Secrets Manager to Use the Key",
      #   Effect = "Allow",
      #   Principal = {
      #     AWS = [
      #       "arn:aws:iam::aws:policy/service-role/AWSServiceRoleForSecretsManager", // AWS Secrets Manager service role
      #       "arn:aws:iam::${var.account_id}:role/ec2_role"                         
      #     ]
      #   },
      #   Action = [
      #     "kms:Encrypt",
      #     "kms:Decrypt",
      #     "kms:ReEncrypt*",
      #     "kms:GenerateDataKey*",
      #     "kms:DescribeKey"
      #   ],
      #   Resource = "*"
      # },
      # {
      #   Sid    = "Allow Management of Grants",
      #   Effect = "Allow",
      #   Principal = {
      #     AWS = [
      #       "arn:aws:iam::aws:policy/service-role/AWSServiceRoleForSecretsManager", // AWS Secrets Manager service role
      #       "arn:aws:iam::${var.account_id}:role/ec2_role"                          // Replace with your specific IAM role for accessing secrets
      #     ]
      #   },
      #   Action = [
      #     "kms:CreateGrant",
      #     "kms:ListGrants",
      #     "kms:RevokeGrant"
      #   ],
      #   Resource = "*",
      #   Condition = {
      #     Bool : {
      #       "kms:GrantIsForAWSResource" : true
      #     }
      #   }
      # }
    ]
  })
}
resource "aws_secretsmanager_secret" "sendgrid_credentials" {
  name       = var.sendgrid_credentials_name
  kms_key_id = aws_kms_key.secrets_manager_key.id
}

resource "aws_secretsmanager_secret_version" "sendgrid_credentials_version" {
  secret_id = aws_secretsmanager_secret.sendgrid_credentials.id
  secret_string = jsonencode({
    sendgrid_api_key         = var.sendgrid_api_key
    sendgrid_verified_sender = var.sendgrid_verified_sender
  })
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret" "db_password_secret" {
  name       = var.rds_db_password
  kms_key_id = aws_kms_key.secrets_manager_key.id
}

resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id     = aws_secretsmanager_secret.db_password_secret.id
  secret_string = jsonencode({ DB_PASS = random_password.db_password.result })
}

data "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id  = aws_secretsmanager_secret.db_password_secret.id
  depends_on = [aws_secretsmanager_secret_version.db_password_version]
}

locals {
  db_password_json = jsondecode(data.aws_secretsmanager_secret_version.db_password_version.secret_string)
}

resource "aws_iam_role_policy_attachment" "attach_secrets_access_policy" {
  policy_arn = aws_iam_policy.secrets_access_policy.arn
  role       = aws_iam_role.ec2_role.id
}