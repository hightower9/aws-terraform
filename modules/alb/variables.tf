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
  description = "VPC for the target group"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Public subnets (two or more AZs)"
}

variable "security_group_id" {
  type        = string
  description = "Security group attached to the ALB"
}

variable "app_port" {
  type        = number
  description = "Instance port the ALB forwards to"
}

variable "health_check_path" {
  type        = string
  description = "Path the ALB polls on each instance"
  default     = "/health"
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS. Empty = HTTP only (local/dev)."
  default     = ""
}

variable "ssl_policy" {
  type        = string
  description = "TLS policy for the HTTPS listener"
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "deletion_protection" {
  type        = bool
  description = "Block accidental deletion of the ALB"
  default     = false
}

variable "deregistration_delay" {
  type        = number
  description = "Seconds the ALB drains in-flight requests from an instance before it is terminated"
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
