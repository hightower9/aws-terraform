variable "project" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (local, dev, uat, prod)"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID for unique bucket naming"
}

variable "force_destroy" {
  type        = bool
  description = "Let destroy delete the buckets even if they contain objects (keep false in prod)"
  default     = false
}

variable "access_log_retention_days" {
  type        = number
  description = "Days to keep S3 access logs"
  default     = 365
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
