#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/user-data.log) 2>&1
echo "=== Cloud-init started at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
echo "=== Environment: ${environment} | App: ${app_name} ==="

CONTAINER_NAME="${container_name}"
IMAGE="${docker_image}:${docker_tag}"
REGION="${aws_region}"
ENV_FILE="/etc/${app_name}/app.env"

# ---- System setup ----
# No `dnf update` here: the AMI (pinned via ami_id in prod) defines the OS
# version, so every instance is identical. Patch by rolling a newer AMI.
# The AWS CLI ships with Amazon Linux 2023.
dnf install -y docker amazon-cloudwatch-agent

# Graceful shutdown: on termination the ASG first deregisters the instance
# from the ALB (which drains in-flight requests for deregistration_delay),
# then systemd stops Docker, which sends SIGTERM to the container and waits
# up to shutdown-timeout seconds before killing it.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DOCKEREOF'
{
  "shutdown-timeout": 30
}
DOCKEREOF

systemctl enable --now docker

# ---- CloudWatch agent: ship this boot log ----
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWEOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "${cloud_init_group}",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# The awslogs driver does not expand placeholders like {instance_id}, so
# resolve the real ID via IMDSv2 to give each instance its own log stream.
IMDS_TOKEN=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -fsS -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  "http://169.254.169.254/latest/meta-data/instance-id")

# ---- App config + secrets from SSM Parameter Store ----
# Every parameter under the path becomes NAME=value in the env file.
echo "=== Loading app config from SSM path ${ssm_parameter_path} ==="
install -d -m 700 "/etc/${app_name}"
aws ssm get-parameters-by-path \
  --region "$REGION" \
  --path "${ssm_parameter_path}" \
  --recursive \
  --with-decryption \
  --query 'Parameters[].[Name,Value]' \
  --output text |
  while IFS=$'\t' read -r NAME VALUE; do
    echo "$(basename "$NAME")=$VALUE"
  done > "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "=== Loaded $(wc -l < "$ENV_FILE") settings: $(cut -d= -f1 "$ENV_FILE" | tr '\n' ' ') ==="

# ---- Registry login (private ECR images only) ----
case "$IMAGE" in
  *.dkr.ecr.*.amazonaws.com/*)
    REGISTRY=$(echo "$IMAGE" | cut -d/ -f1)
    echo "=== Logging in to $REGISTRY ==="
    aws ecr get-login-password --region "$REGION" |
      docker login --username AWS --password-stdin "$REGISTRY"
    ;;
esac

# ---- Pull and run the container ----
echo "=== Pulling Docker image: $IMAGE ==="
docker pull "$IMAGE"

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "=== Starting container (log stream: $INSTANCE_ID) ==="
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p ${app_port}:${container_port} \
  --env-file "$ENV_FILE" \
  --log-driver=awslogs \
  --log-opt awslogs-region="$REGION" \
  --log-opt awslogs-group="${app_log_group}" \
  --log-opt awslogs-stream="$INSTANCE_ID" \
  "$IMAGE"

# ---- Report app health in the boot log ----
# The ALB health check is what actually gates traffic and instance refresh;
# this loop just makes a failed boot obvious in the cloud-init log group.
HEALTH_URL="http://localhost:${app_port}${health_check_url}"
START=$(date +%s)
WAIT_LIMIT="${startup_timeout}"
echo "=== Waiting up to $WAIT_LIMIT seconds for app health at $HEALTH_URL ==="

while [ $(( $(date +%s) - START )) -lt "$WAIT_LIMIT" ]; do
  if curl -fsS --max-time 5 -o /dev/null "$HEALTH_URL"; then
    echo "=== App healthy after $(( $(date +%s) - START ))s ==="
    echo "=== Cloud-init finished at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
    exit 0
  fi
  sleep 5
done

echo "ERROR: app never became healthy within $WAIT_LIMIT seconds. Logs:" >&2
docker logs --tail 50 "$CONTAINER_NAME" >&2 || true
exit 1
