variable "region" {
  type        = string
  description = "The AWS region to deploy resources"
}

variable "project_name" {
  type = string
}

variable "vpc_count" {
  type = number
}

variable "base_cidr_block" {
  type = string
}

variable "app_port" {
  type = number
}

variable "custom_ami_id" {
  type = string
}