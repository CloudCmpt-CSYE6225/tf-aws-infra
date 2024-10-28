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