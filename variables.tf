variable "region" {
  type        = string
  description = "The AWS region to deploy resources"
}

variable "project_name" {
  type = string
}

variable "vpc_count" {
  type    = number
  default = 1
}

variable "base_cidr_block" {
  type = string
}

variable "app_port" {
  type        = number
  description = "Port on which the application runs"
  default     = 3000
}

variable "custom_ami_id" {
  type = string
}

variable "db_username" {
  type        = string
  description = "Username for the RDS instance"
}

variable "db_password" {
  type        = string
  description = "Password for the RDS instance"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "domain_name" {
  description = "Base domain name"
  type        = string
}

variable "environment" {
  description = "Environment (dev or demo)"
  type        = string
  validation {
    condition     = contains(["dev", "demo"], var.environment)
    error_message = "Environment must be either 'dev' or 'demo'."
  }
}

variable "sendgrid_api_key" {
  description = "SendGrid API Key"
  type        = string
  sensitive   = true
}

variable "sendgrid_verified_sender" {
  description = "SendGrid verified sender email"
  type        = string
  default     = "no-reply@srijithmakam.me"
}

variable "desired_capacity" {
  description = "Desired capacity of the autoscaling group"
  type        = number
  default     = 3
}

variable "max_capacity" {
  description = "Maximum capacity of the autoscaling group"
  type        = number
  default     = 5
}

variable "min_capacity" {
  description = "Minimum capacity of the autoscaling group"
  type        = number
  default     = 3

}

variable "scale_up_threshold" {
  description = "Scale up threshold for the autoscaling group"
  type        = string
  default     = "9"
}

variable "scale_down_threshold" {
  description = "Scale down threshold for the autoscaling group"
  type        = string
  default     = "7"

}

variable "scale_down_adjustment" {
  description = "Scale down adjustment for the autoscaling group"
  type        = number
  default     = -1
}

variable "scale_up_adjustment" {
  description = "Scale up adjustment for the autoscaling group"
  type        = number
  default     = 1
}

variable "cooldown" {
  description = "Cooldown period for the autoscaling group"
  type        = number
  default     = 60

}

variable "file_path" {
  description = "Path to the file to be uploaded to S3"
  type        = string
}

variable "sendgrid_credentials_name" {
  description = "Name of the secret in Secrets Manager"
  type        = string
}

variable "rds_db_password_name" {
  description = "Password name for the RDS instance"
  type        = string

}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}