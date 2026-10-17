# One root configuration for every environment. Per-environment values
# live in environments/<env>/terraform.tfvars and the state location in
# environments/<env>/backend.tfbackend; the Makefile wires them together:
#   make init|plan|apply ENV=<local|dev|uat|prod> [EMULATOR=1]
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }

  # Partial config: bucket/key/region come from the env's backend.tfbackend.
  # use_lockfile = S3-native state locking (no DynamoDB table needed).
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "laravel-aws"
  }

  # Default app environment; anything in var.app_settings overrides it.
  default_app_settings = {
    APP_NAME           = var.project
    APP_ENV            = var.environment == "prod" ? "production" : var.environment
    APP_DEBUG          = var.environment == "prod" ? "false" : "true"
    LOG_CHANNEL        = "stderr"
    FILESYSTEM_DISK    = "s3"
    AWS_DEFAULT_REGION = var.aws_region
    AWS_BUCKET         = module.s3.bucket_id
  }
}
