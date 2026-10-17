# Values are set per environment in environments/<env>/terraform.tfvars.
# Defaults here are the safe/production-leaning choice; tfvars override.

# ---------------- Identity ----------------

variable "project" {
  type        = string
  description = "Project name, used in every resource name"
  default     = "laravel"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project))
    error_message = "project must be lowercase letters, digits and dashes (max 21 chars)."
  }
}

variable "environment" {
  type        = string
  description = "Environment name"

  validation {
    condition     = contains(["local", "dev", "uat", "prod"], var.environment)
    error_message = "environment must be one of: local, dev, uat, prod."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

# ---------------- Network ----------------

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR (non-overlapping per environment)"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "One public subnet per AZ (at least two, for the ALB)"
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs matched by index to public_subnet_cidrs"
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "Who may reach the ALB on 80/443"
  default     = ["0.0.0.0/0"]
}

variable "enable_flow_logs" {
  type        = bool
  description = "Send VPC flow logs to CloudWatch"
  default     = true
}

# ---------------- Load balancer / TLS ----------------

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate for HTTPS. Empty = HTTP only (fine for local/dev, required for prod)."
  default     = ""
}

variable "alb_deletion_protection" {
  type        = bool
  description = "Block accidental deletion of the ALB"
  default     = true
}

# ---------------- Compute ----------------

variable "instance_type" {
  type        = string
  description = "EC2 instance type (a change rolls instances with zero downtime)"
}

variable "ami_id" {
  type        = string
  description = "Pinned AMI. Empty = latest Amazon Linux 2023 at plan time."
  default     = ""
}

variable "key_name" {
  type        = string
  description = "Optional SSH key pair. Leave null: use SSM Session Manager."
  default     = null
}

variable "asg_min_size" {
  type        = number
  description = "ASG minimum instances"
  default     = 1
}

variable "asg_max_size" {
  type        = number
  description = "ASG maximum instances (>= 2x desired for zero-downtime refresh)"
  default     = 2
}

variable "asg_desired_capacity" {
  type        = number
  description = "ASG steady-state instances"
  default     = 1
}

variable "health_check_type" {
  type        = string
  description = "ELB (app health via ALB) or EC2 (VM status only)"
  default     = "ELB"
}

variable "health_check_grace_period" {
  type        = number
  description = "Seconds before a new instance is health-checked"
  default     = 300
}

# ---------------- Application ----------------

variable "docker_image" {
  type        = string
  description = "Image repository (ECR URL in real environments)"
}

variable "docker_tag" {
  type        = string
  description = "Immutable image tag, e.g. a git SHA"
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

variable "health_check_url" {
  type        = string
  description = "Path that must return 2xx/3xx for an instance to receive traffic"
  default     = "/health"
}

variable "startup_timeout" {
  type        = number
  description = "Seconds the boot script waits for the app before logging a failure"
  default     = 300
}

variable "create_ecr_repository" {
  type        = bool
  description = "Create an ECR repository for this environment"
  default     = true
}

variable "app_settings" {
  type        = map(string)
  description = "Extra non-secret app env vars (stored in SSM; override the defaults in main.tf)"
  default     = {}
}

variable "app_secret_placeholders" {
  type        = map(string)
  description = "Secret env vars created in SSM with a placeholder; set real values with `aws ssm put-parameter --overwrite`"
  default     = {}
  sensitive   = true
}

# ---------------- Operations ----------------

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention"
  default     = 30
}

variable "alarm_email" {
  type        = string
  description = "Email that receives alarms. Empty = SNS topic without subscribers."
  default     = ""
}

variable "force_destroy" {
  type        = bool
  description = "Let destroy delete non-empty buckets/registries. Never true in prod."
  default     = false

  validation {
    condition     = !(var.force_destroy && var.environment == "prod")
    error_message = "force_destroy must stay false in prod."
  }
}
