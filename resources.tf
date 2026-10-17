module "vpc" {
  source = "./modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
  enable_flow_logs    = var.enable_flow_logs
  log_retention_days  = var.log_retention_days
  tags                = local.common_tags
}

module "security_group" {
  source = "./modules/security_group"

  project               = var.project
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  app_port              = var.app_port
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
  tags                  = local.common_tags
}

module "alb" {
  source = "./modules/alb"

  project             = var.project
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.public_subnet_ids
  security_group_id   = module.security_group.alb_security_group_id
  app_port            = var.app_port
  health_check_path   = var.health_check_url
  certificate_arn     = var.acm_certificate_arn
  deletion_protection = var.alb_deletion_protection
  tags                = local.common_tags
}

module "s3" {
  source = "./modules/s3"

  project        = var.project
  environment    = var.environment
  aws_account_id = local.account_id
  force_destroy  = var.force_destroy
  tags           = local.common_tags
}

module "ecr" {
  source = "./modules/ecr"
  count  = var.create_ecr_repository ? 1 : 0

  project      = var.project
  environment  = var.environment
  force_delete = var.force_destroy
  tags         = local.common_tags
}

module "app_config" {
  source = "./modules/app_config"

  project             = var.project
  environment         = var.environment
  settings            = merge(local.default_app_settings, var.app_settings)
  secret_placeholders = var.app_secret_placeholders
  tags                = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  project             = var.project
  environment         = var.environment
  aws_region          = var.aws_region
  aws_account_id      = local.account_id
  s3_bucket_arn       = module.s3.bucket_arn
  ssm_parameter_path  = module.app_config.path
  ecr_repository_arns = module.ecr[*].repository_arn
  tags                = local.common_tags
}

module "ec2" {
  source = "./modules/ec2"

  project                   = var.project
  environment               = var.environment
  instance_type             = var.instance_type
  ami_id                    = var.ami_id
  subnet_ids                = module.vpc.public_subnet_ids
  security_group_id         = module.security_group.instance_security_group_id
  target_group_arn          = module.alb.target_group_arn
  instance_profile_name     = module.iam.instance_profile_name
  key_name                  = var.key_name
  docker_image              = var.docker_image
  docker_tag                = var.docker_tag
  app_port                  = var.app_port
  container_port            = var.container_port
  aws_region                = var.aws_region
  ssm_parameter_path        = module.app_config.path
  log_retention_days        = var.log_retention_days
  asg_min_size              = var.asg_min_size
  asg_max_size              = var.asg_max_size
  asg_desired_capacity      = var.asg_desired_capacity
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  health_check_url          = var.health_check_url
  startup_timeout           = var.startup_timeout

  tags = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  project                 = var.project
  environment             = var.environment
  asg_name                = module.ec2.asg_name
  alb_arn_suffix          = module.alb.arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  alarm_email             = var.alarm_email
  tags                    = local.common_tags
}
