# ============================================================
# uat: production-like. Works as-is on Floci (EMULATOR=1).
# Lines marked "# PLACEHOLDER" are dummies to replace before a real
# uat deploy (see docs/PRODUCTION.md). `make plan ENV=uat` warns on them.
# ============================================================
environment = "uat"
aws_region  = "us-east-1"

vpc_cidr            = "10.30.0.0/16"
public_subnet_cidrs = ["10.30.1.0/24", "10.30.2.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b"]

instance_type = "t3.small"
ami_id        = "" # PLACEHOLDER: pin the AMI prod will get (from `make output`: ami_id)

docker_image     = "nginx"       # PLACEHOLDER: ECR URL from `make output` (ecr_repository_url)
docker_tag       = "1.27-alpine" # PLACEHOLDER: immutable tag you pushed, e.g. git SHA
container_port   = 80            # PLACEHOLDER: 8000 for the Laravel image
health_check_url = "/"           # PLACEHOLDER: /health for the Laravel image

asg_min_size         = 1
asg_max_size         = 2
asg_desired_capacity = 1

alb_deletion_protection = false
log_retention_days      = 30

acm_certificate_arn = "" # PLACEHOLDER: ACM certificate ARN for the uat domain
alarm_email         = "" # PLACEHOLDER: team inbox for alarms

app_secret_placeholders = {
  APP_KEY     = "base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" # set the real value in SSM, not here
  DB_PASSWORD = "change-me"                                           # set the real value in SSM, not here
}
