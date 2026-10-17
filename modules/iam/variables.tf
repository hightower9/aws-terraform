variable "project" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (local, dev, uat, prod)"
}

variable "aws_region" {
  type        = string
  description = "Region used to scope log group and SSM ARNs"
}

variable "aws_account_id" {
  type        = string
  description = "Account used to scope log group and SSM ARNs"
}

variable "s3_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket for app storage"
}

variable "ssm_parameter_path" {
  type        = string
  description = "SSM path the instance may read app config from (e.g. /laravel/dev/app)"
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ECR repositories the instance may pull from"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
