# ============================================================
# prod: works as-is on Floci (EMULATOR=1) for testing.
# Every line marked "# PLACEHOLDER" MUST be replaced (and the marker
# removed) before a real prod deploy: `make plan ENV=prod` refuses to
# run while any are left. Walkthrough: docs/PRODUCTION.md
# ============================================================
environment = "prod"
aws_region  = "us-east-1"

vpc_cidr            = "10.40.0.0/16"
public_subnet_cidrs = ["10.40.1.0/24", "10.40.2.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b"]

instance_type = "t3.medium"
ami_id        = "" # PLACEHOLDER: pinned AMI ID (copy the one tested in uat)

docker_image     = "nginx"       # PLACEHOLDER: ECR URL from `make output` (ecr_repository_url)
docker_tag       = "1.27-alpine" # PLACEHOLDER: immutable tag you pushed, e.g. git SHA
container_port   = 80            # PLACEHOLDER: 8000 for the Laravel image
health_check_url = "/"           # PLACEHOLDER: /health for the Laravel image

# Two instances in two AZs; max = 2x desired for zero-downtime refresh.
asg_min_size         = 2
asg_max_size         = 4
asg_desired_capacity = 2

alb_deletion_protection = true
force_destroy           = false
log_retention_days      = 90

acm_certificate_arn = "" # PLACEHOLDER: ACM certificate ARN for the prod domain (required)
alarm_email         = "" # PLACEHOLDER: on-call / team inbox for alarms (required)

app_settings = {
  APP_URL = "https://example.com" # PLACEHOLDER: your prod domain
}

app_secret_placeholders = {
  APP_KEY     = "base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" # set the real value in SSM, not here
  DB_PASSWORD = "change-me"                                           # set the real value in SSM, not here
}
