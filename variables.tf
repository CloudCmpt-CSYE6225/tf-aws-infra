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

variable "subnet_count" {
  type = number
}