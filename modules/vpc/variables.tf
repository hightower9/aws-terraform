variable "project" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (local, dev, uat, prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "One public subnet CIDR per availability zone (at least two, for the ALB)"

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2 && alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Provide at least two valid CIDR blocks."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones, matched by index to public_subnet_cidrs"
}

variable "enable_flow_logs" {
  type        = bool
  description = "Send VPC flow logs to CloudWatch"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Retention for the flow-log group"
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
