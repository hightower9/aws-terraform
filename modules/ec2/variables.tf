variable "project" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (local, dev, uat, prod)"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type (a change triggers a zero-downtime instance refresh)"
  default     = "t3.micro"
}

variable "ami_id" {
  type        = string
  description = "Pinned AMI ID. Empty = latest Amazon Linux 2023 (a new AMI then triggers a refresh)"
  default     = ""
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets (one per AZ) the ASG spreads instances across"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID for the EC2 instances"
}

variable "target_group_arn" {
  type        = string
  description = "ALB target group the ASG registers instances in"
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name"
}

variable "key_name" {
  type        = string
  description = "Optional SSH key pair name. Leave null and use SSM Session Manager instead."
  default     = null
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GB"
  default     = 30
}

variable "docker_image" {
  type        = string
  description = "Docker image (e.g. <account>.dkr.ecr.<region>.amazonaws.com/laravel-prod)"
}

variable "docker_tag" {
  type        = string
  description = "Docker image tag (use an immutable tag such as a git SHA)"
}

variable "app_port" {
  type        = number
  description = "Host port the ALB forwards to"
  default     = 8000
}

variable "container_port" {
  type        = number
  description = "Port the app listens on inside the container"
  default     = 8000
}

variable "aws_region" {
  type        = string
  description = "AWS region for resource lookups from within EC2"
}

variable "ssm_parameter_path" {
  type        = string
  description = "SSM path whose parameters are loaded into the container environment"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 30
}

# ---------------- Zero-downtime / ASG settings ----------------

variable "asg_min_size" {
  type        = number
  description = "ASG minimum size"
  default     = 1
}

variable "asg_max_size" {
  type        = number
  description = "ASG maximum size. Must be >= 2x desired so a refresh can launch replacements before terminating old instances."
  default     = 2
}

variable "asg_desired_capacity" {
  type        = number
  description = "ASG desired capacity (steady-state instance count)"
  default     = 1
}

variable "health_check_type" {
  type        = string
  description = "ASG health check type. ELB (default) uses the ALB's app health check."
  default     = "ELB"

  validation {
    condition     = contains(["ELB", "EC2"], var.health_check_type)
    error_message = "health_check_type must be ELB or EC2."
  }
}

variable "health_check_grace_period" {
  type        = number
  description = "Seconds to wait before health-checking a freshly launched instance (gives the container time to boot)"
  default     = 300
}

variable "health_check_url" {
  type        = string
  description = "App path checked by the ALB and logged by the boot script"
  default     = "/health"
}

variable "startup_timeout" {
  type        = number
  description = "Seconds the boot script waits for the app before logging a failure"
  default     = 300
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
