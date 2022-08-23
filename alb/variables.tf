variable "name" { 
}

variable "environment" {
  description = "Name of the environment"
}

variable "subnets" {
  description = "Comma separated list of subnet IDs"
}

variable "vpc_id" {
  description = "VPC ID"
}

variable "alb_security_groups" {
  description = "Comma separated list of security groups"
}

variable "health_check_path" {
  description = "Path to check if the service is healthy"
}