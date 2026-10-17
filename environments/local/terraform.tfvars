# ============================================================
# local: runs ONLY on the Floci emulator (make ... ENV=local).
# Every value here is a working dummy; nothing needs changing.
# ============================================================
environment = "local"
aws_region  = "us-east-1"

vpc_cidr            = "10.10.0.0/16"
public_subnet_cidrs = ["10.10.1.0/24", "10.10.2.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b"]

instance_type = "t3.micro"

# Stand-in for the Laravel image: public nginx listens on 80 and serves "/".
docker_image     = "nginx"
docker_tag       = "1.27-alpine"
container_port   = 80
health_check_url = "/"

asg_min_size         = 1
asg_max_size         = 2
asg_desired_capacity = 1

alb_deletion_protection = false
force_destroy           = true
log_retention_days      = 7

# Dummy (all-zero) Laravel key so a real Laravel image can boot locally.
app_secret_placeholders = {
  APP_KEY = "base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
}
