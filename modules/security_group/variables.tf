variable "project" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (local, dev, uat, prod)"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC where the security groups will be created"
}

variable "app_port" {
  type        = number
  description = "Instance port the ALB forwards to"
  default     = 8000
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the ALB on 80/443"
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_ingress_cidrs) > 0 && alltrue([for c in var.allowed_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "Provide at least one valid CIDR block."
  }
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
