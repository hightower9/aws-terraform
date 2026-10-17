variable "project" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (local, dev, uat, prod)"
}

variable "asg_name" {
  type        = string
  description = "Auto Scaling Group to watch"
}

variable "alb_arn_suffix" {
  type        = string
  description = "ALB ARN suffix (metric dimension)"
}

variable "target_group_arn_suffix" {
  type        = string
  description = "Target group ARN suffix (metric dimension)"
}

variable "alarm_email" {
  type        = string
  description = "Email subscribed to alarms. Empty = topic only."
  default     = ""
}

variable "cpu_threshold" {
  type        = number
  description = "CPU % that triggers the cpu-high alarm"
  default     = 80
}

variable "error_5xx_threshold" {
  type        = number
  description = "5xx responses per 5 minutes that trigger the error alarms"
  default     = 10
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
