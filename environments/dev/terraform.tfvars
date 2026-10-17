# ============================================================
# dev: works as-is on Floci (EMULATOR=1) and on real AWS with the
# nginx stand-in. Lines marked "# PLACEHOLDER" are dummies to replace
# before dev runs the real app (see docs/PRODUCTION.md).
# `make plan ENV=dev` (real AWS) lists any placeholders left as warnings.
# ============================================================
environment = "dev"
aws_region  = "us-east-1"

vpc_cidr            = "10.20.0.0/16"
public_subnet_cidrs = ["10.20.1.0/24", "10.20.2.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b"]

instance_type = "t3.small"

docker_image     = "nginx"       # PLACEHOLDER: ECR URL from `make output` (ecr_repository_url)
docker_tag       = "1.27-alpine" # PLACEHOLDER: immutable tag you pushed, e.g. git SHA
container_port   = 80            # PLACEHOLDER: 8000 for the Laravel image
health_check_url = "/"           # PLACEHOLDER: /health for the Laravel image

asg_min_size         = 1
asg_max_size         = 2
asg_desired_capacity = 1

alb_deletion_protection = false
force_destroy           = true
log_retention_days      = 14

acm_certificate_arn = "" # optional in dev: HTTP only without it
alarm_email         = "" # optional in dev

app_secret_placeholders = {
  APP_KEY = "base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" # set the real value in SSM, not here
}
