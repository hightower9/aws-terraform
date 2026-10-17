# Going to Production

Step by step from "works on Floci" to a live, HTTPS, zero-downtime prod. The same steps apply to `uat` (and `dev` if you want it to run the real app).

**The idea:** every environment ships with dummy values that work on Floci (an nginx stand-in, no certificate, no alarm email). Each dummy that must change for real use is marked `# PLACEHOLDER` in `environments/<env>/terraform.tfvars` and `backend.tfbackend`. Going live is mostly replacing those values. `make plan ENV=prod` **refuses to run while any placeholder is left**. For dev and uat it only warns.

```bash
bash scripts/preflight.sh prod     # shows exactly what is still missing
```

- [0. Before you start](#0-before-you-start)
- [1. Rehearse on Floci](#1-rehearse-on-floci)
- [2. AWS account and credentials](#2-aws-account-and-credentials)
- [3. State bucket](#3-state-bucket)
- [4. TLS certificate](#4-tls-certificate)
- [5. Fill in the placeholders](#5-fill-in-the-placeholders)
- [6. Create the registry and config, push the image, set secrets](#6-create-the-registry-and-config-push-the-image-set-secrets)
- [7. Full deploy](#7-full-deploy)
- [8. DNS and alarms](#8-dns-and-alarms)
- [9. Verify](#9-verify)
- [Day-2 operations](#day-2-operations)
- [Your Laravel image: requirements](#your-laravel-image-requirements)
- [Database](#database)
- [CI access (GitHub OIDC)](#ci-access-github-oidc)
- [Optional hardening](#optional-hardening)
- [Go-live checklist](#go-live-checklist)

---

## What you get

```
                 Internet
                    │  HTTPS (443) · HTTP (80) → redirect
          ┌─────────▼──────────┐
          │  Application LB    │  stable DNS name, TLS (ACM), health checks /health
          └───┬────────────┬───┘
     us-east-1a           us-east-1b
   ┌──────────┐          ┌──────────┐
   │ EC2 + app│          │ EC2 + app│   Auto Scaling Group (prod: 2–4 instances)
   │ container│          │ container│   only reachable from the ALB, no SSH (SSM)
   └────┬─────┘          └────┬─────┘
        └─── S3 (storage) · ECR (image) · SSM (config/secrets) · CloudWatch (logs, alarms → SNS email)
```

- **Zero-downtime deploys:**
  - Any change to the instance definition (`docker_tag`, `instance_type`, `ami_id`, config) rolls instances using `min_healthy_percentage = 100` and `max_healthy_percentage = 200`.
  - New instances must pass the ALB health check before old ones are terminated.
  - A failed rollout **rolls back automatically**.
- **Graceful shutdown:** the ALB drains an instance for 30s, then Docker gives the container another 30s after SIGTERM.

---

## 0. Before you start

| You need | Notes |
|---|---|
| An AWS account for prod | A **separate account per environment** is best practice; at minimum keep prod separate. |
| A domain you control | For the HTTPS certificate and the app URL. |
| Tools | Terraform ≥ 1.10, AWS CLI v2, Docker, make, bash (Git Bash on Windows). For shell access to instances: the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html). |
| Your Laravel image | Must meet the [requirements below](#your-laravel-image-requirements). |

---

## 1. Rehearse on Floci

Run prod's exact configuration on the emulator first. It's free and catches wiring mistakes:

```bash
make start-floci
make test-env ENV=prod          # bootstrap + init + plan + apply + app test, all on Floci
make floci-ui                   # browse what it created
```

Build your image and test it with prod's settings (ports, health path, SSM env):

```bash
docker build -t laravel-app:rehearsal /path/to/laravel-app
IMAGE=laravel-app:rehearsal make test-app ENV=prod
```

Emulator runs skip the preflight and turn off ALB deletion protection so they stay disposable. Nothing touches AWS.

---

## 2. AWS account and credentials

```bash
aws configure sso --profile laravel-prod      # or: aws configure --profile laravel-prod
export AWS_PROFILE=laravel-prod               # or put it in .env
aws sts get-caller-identity                   # CHECK the account ID before every prod step
```

Everything below assumes `AWS_PROFILE` points at the prod account.

---

## 3. State bucket

S3 bucket names are global, so pick a unique one. Edit `environments/prod/backend.tfbackend`:

```hcl
bucket = "laravel-tf-state-prod-123456789012"   # e.g. append your account ID; remove the PLACEHOLDER comment
key    = "terraform.tfstate"
region = "us-east-1"
```

Create it (versioned, KMS-encrypted, public access blocked, TLS-only). Locking uses an S3 lockfile, so no DynamoDB table is needed:

```bash
make bootstrap-state ENVS=prod
make init ENV=prod
```

---

## 4. TLS certificate

Request a certificate in **the same region** as the stack and validate it through DNS:

```bash
aws acm request-certificate --region us-east-1 \
  --domain-name app.example.com --validation-method DNS
# → CertificateArn
aws acm describe-certificate --region us-east-1 --certificate-arn <arn> \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
# add that CNAME record at your DNS provider, wait until:
aws acm describe-certificate --certificate-arn <arn> --query Certificate.Status   # "ISSUED"
```

Once `acm_certificate_arn` is set, the ALB serves HTTPS and port 80 permanently redirects to it.

---

## 5. Fill in the placeholders

Edit `environments/prod/terraform.tfvars`. Replace every `# PLACEHOLDER` value **and delete the marker comment**:

| Setting | Set it to | How to get it |
|---|---|---|
| `docker_image` | `<account-id>.dkr.ecr.us-east-1.amazonaws.com/laravel-prod` | Predictable: Terraform creates this repo in step 6 |
| `docker_tag` | An immutable tag, e.g. the git SHA `3f9c2ab` | You choose it when you push (step 6). Never `latest`. |
| `container_port` | `8000` (or whatever your image listens on) | Your Dockerfile |
| `health_check_url` | `/health`, or `/up` (Laravel 11+ built-in route) | Must return 2xx/3xx without auth or DB-heavy work |
| `ami_id` | e.g. `ami-0abc...` | `make output ENV=uat` → `ami_id` (the AMI you tested in uat), or `aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text` |
| `acm_certificate_arn` | The ARN from step 4 | |
| `alarm_email` | Your on-call / team inbox | |
| `app_settings.APP_URL` | `https://app.example.com` | Your domain |

Also review the settings that aren't placeholders:

| Setting | Default in prod | Change if… |
|---|---|---|
| `instance_type` | `t3.medium` | you need more or less capacity (changing it later is a zero-downtime roll) |
| `asg_min_size` / `asg_desired_capacity` / `asg_max_size` | `2` / `2` / `4` | Keep `max ≥ 2 × desired`, or refreshes can't launch replacements first. |
| `allowed_ingress_cidrs` | `["0.0.0.0/0"]` | the app is internal-only (e.g. office/VPN CIDRs) |
| `availability_zones` | `us-east-1a`, `us-east-1b` | you use another region |
| `log_retention_days` | `90` | compliance needs differ |

```bash
bash scripts/preflight.sh prod    # must print "preflight [prod]: OK"
```

---

## 6. Create the registry and config, push the image, set secrets

There's a chicken-and-egg problem: instances must find a real image and real secrets the moment they boot. So create the registry and the SSM config first, fill them, and only then launch instances.

**6a. Create only ECR + SSM config (and the S3 bucket they reference):**

```bash
make plan  ENV=prod TF_ARGS='-target=module.ecr -target=module.app_config'
make apply ENV=prod
make output ENV=prod      # note ecr_repository_url and ssm_parameter_path
```

Terraform warns that `-target` is for exceptional use. This bootstrap is that exception, and step 7 applies everything.

**6b. Build and push the image** (the tag must match `docker_tag`):

```bash
REPO=$(make -s output ENV=prod | sed -n 's/^ecr_repository_url = "\(.*\)"/\1/p')
TAG=3f9c2ab                                    # = docker_tag in tfvars
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build -t "$REPO:$TAG" /path/to/laravel-app
docker push "$REPO:$TAG"
```

ECR tags are **immutable**: a tag can't be overwritten, so every release gets a new one. Pushed images are scanned automatically:

```bash
aws ecr describe-image-scan-findings --repository-name laravel-prod --image-id imageTag=$TAG
```

**6c. Set the real secrets.** Terraform created them with dummy values and will never overwrite what you set:

```bash
# On Windows Git Bash prefix with MSYS_NO_PATHCONV=1 so /laravel/... isn't rewritten
aws ssm put-parameter --overwrite --type SecureString \
  --name /laravel/prod/app/APP_KEY --value "base64:$(openssl rand -base64 32)"
aws ssm put-parameter --overwrite --type SecureString \
  --name /laravel/prod/app/DB_PASSWORD --value '<real password>'
```

Add any other env var the same way (`--type String` for non-secrets, or add it to `app_settings` in tfvars). Every parameter under `/laravel/prod/app/` becomes an environment variable in the container. To add a new secret name, put it in `app_secret_placeholders` (so Terraform tracks it), apply, then `put-parameter --overwrite` it.

---

## 7. Full deploy

```bash
make plan  ENV=prod       # READ IT: expect only creations on a first deploy
make apply ENV=prod
make output ENV=prod      # app_url, alb_dns_name, asg_name, ...
```

The first boot takes a few minutes: package install, image pull, then health checks. Watch it:

```bash
TG=$(make -s output ENV=prod | sed -n 's/^target_group_arn = "\(.*\)"/\1/p')
aws elbv2 describe-target-health --target-group-arn "$TG" --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table
aws logs tail /ec2/laravel/prod/cloud-init --follow     # boot log of every instance
```

---

## 8. DNS and alarms

- **DNS:** point your domain at the ALB.
  - Route 53: an **alias A record** to `alb_dns_name` with `alb_zone_id`.
  - Elsewhere: a **CNAME** to `alb_dns_name`.

  The name never changes when instances are replaced.
- **Alarms:** AWS sends a confirmation email to `alarm_email`. **Click the link** or no alarm will ever arrive. You'll get alerts for:
  - no healthy hosts (site down)
  - an unhealthy host
  - app 5xx > 10 in 5 min
  - ALB 5xx > 10 in 5 min
  - CPU > 80% for 10 min

---

## 9. Verify

```bash
curl -I https://app.example.com/health                    # 200
curl -I http://app.example.com                            # 301 → https
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg_name> \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,HealthStatus]' --output table
aws logs tail /ec2/laravel/prod/app --follow              # container logs (one stream per instance)
aws ssm start-session --target <instance-id>              # shell on an instance (no SSH)
```

---

## Day-2 operations

### Release a new version (zero downtime)

```bash
TAG=$(git rev-parse --short HEAD)
docker build -t "$REPO:$TAG" . && docker push "$REPO:$TAG"
# set docker_tag = "<TAG>" in environments/prod/terraform.tfvars (commit it)
make plan ENV=prod     # shows the launch template + ASG change
make apply ENV=prod    # starts the rolling instance refresh
aws autoscaling describe-instance-refreshes --auto-scaling-group-name <asg_name> \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]'
```

`apply` returns once the refresh has *started*; AWS completes it in the background. If the new version never gets healthy, the refresh **rolls back** to the previous launch template automatically.

**Rollback by hand:** set `docker_tag` back to the previous tag, then plan and apply. That's another zero-downtime roll.

**One-off override without editing the file:** `make plan ENV=prod TF_ARGS='-var docker_tag=3f9c2ab'`.

### Change a config value or secret

```bash
aws ssm put-parameter --overwrite --type SecureString --name /laravel/prod/app/DB_PASSWORD --value '...'
aws autoscaling start-instance-refresh --auto-scaling-group-name <asg_name> \
  --preferences '{"MinHealthyPercentage":100,"MaxHealthyPercentage":200}'
```

Instances read SSM at boot, so a refresh rolls the new value out with zero downtime.

### Patch the OS

Put the new AMI in `ami_id` for **uat**, then plan and apply, and test. Then copy the same `ami_id` to prod, plan and apply. Both are rolling replacements.

### Resize

Change `instance_type` (vertical) or `asg_*` sizes (horizontal; keep max ≥ 2 × desired), then plan and apply.

### Tear down prod

The ALB has deletion protection and the buckets aren't force-deleted, both on purpose. To really delete everything:

```bash
make plan ENV=prod TF_ARGS='-var alb_deletion_protection=false' && make apply ENV=prod
# empty the S3 buckets and ECR repo first, then:
make destroy ENV=prod CONFIRM=prod TF_ARGS='-var alb_deletion_protection=false'
```

---

## Your Laravel image: requirements

| Requirement | Why |
|---|---|
| Serves HTTP on `container_port` (default 8000) | The instance maps `app_port` 8000 to this port, and the ALB forwards to it. |
| `GET <health_check_url>` returns 2xx/3xx quickly, without auth | The ALB health check gates traffic and deploys. Laravel 11+ ships `/up`. |
| Reads config from environment variables | Everything under `/laravel/<env>/app/` in SSM is passed as env vars (`APP_KEY`, `DB_*`, `AWS_BUCKET`, …). |
| Logs to stdout/stderr (`LOG_CHANNEL=stderr`, set by default) | The Docker awslogs driver ships stdout/stderr to CloudWatch. Files inside the container are lost. |
| Stores uploads on S3 (`FILESYSTEM_DISK=s3`, set by default) | Instances are disposable; local disk is wiped on every deploy. |
| Uses the AWS SDK's default credentials (no keys in env) | The instance role grants access to the app bucket only. |
| Trusts the ALB proxy | Configure Laravel's `TrustProxies` (e.g. `$middleware->trustProxies(at: '*')`) so `https://` URLs and client IPs are correct. |
| Handles SIGTERM | Finish in-flight work within 30s (php-fpm/Octane do this by default). |
| Stateless sessions/cache (`SESSION_DRIVER`, `CACHE_STORE` = database/redis) | Requests are spread across instances. |

---

## Database

This stack doesn't create a database. Laravel needs one, so pick an option:

- **Amazon RDS / Aurora (recommended):** create it in the same VPC (add private subnets) or in a shared network stack. Allow port 3306/5432 from the instance security group (`module.security_group.instance_security_group_id`).
- **Existing or managed DB elsewhere:** just configure the connection.

Either way, pass the connection in through SSM:

```hcl
# environments/prod/terraform.tfvars
app_settings = {
  APP_URL       = "https://app.example.com"
  DB_CONNECTION = "mysql"
  DB_HOST       = "prod-db.xxxx.us-east-1.rds.amazonaws.com"
  DB_PORT       = "3306"
  DB_DATABASE   = "laravel"
  DB_USERNAME   = "laravel"
}
# DB_PASSWORD stays a secret: set it with `aws ssm put-parameter` (step 6c)
```

Run migrations as a deploy step, e.g. from an SSM session: `docker exec laravel-prod-app php artisan migrate --force`.

---

## CI access (GitHub OIDC)

The workflow in `.github/workflows/terraform.yml` is **manual only**. Start it from GitHub → Actions → *Terraform CI* → *Run workflow*. It always runs fmt, validate, preflight and Checkov. If you pick an environment, it also runs a real `plan` and shows it in the run summary.

For the plan step, give GitHub a short-lived role instead of access keys:

1. In the target account, create the GitHub OIDC provider (`token.actions.githubusercontent.com`, audience `sts.amazonaws.com`).
2. Create a role trusted by it, restricted to your repo:
   ```json
   {
     "Effect": "Allow",
     "Principal": { "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com" },
     "Action": "sts:AssumeRoleWithWebIdentity",
     "Condition": {
       "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
       "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:<org>/<repo>:*" }
     }
   }
   ```
   Attach `ReadOnlyAccess` plus read/write on the state bucket (plan needs to take the lock).
3. Add the role ARN as the repository secret **`AWS_ROLE_ARN`**.

To make CI automatic again, add a `pull_request:` trigger at the top of the workflow (see the comment there).

---

## Optional hardening

These are recorded as accepted risks in `.checkov.yml`. Enable them if your requirements call for it, then remove the matching skip line:

| Hardening | Check | How |
|---|---|---|
| WAF on the ALB | CKV2_AWS_28 | `aws_wafv2_web_acl` (AWS managed rule groups) + `aws_wafv2_web_acl_association` with `module.alb` |
| ALB access logs | CKV_AWS_91 | A separate SSE-S3 bucket with the ELB log-delivery policy; set `access_logs` on `aws_lb` |
| Customer-managed KMS keys | CKV_AWS_158, CKV_AWS_337 | A `aws_kms_key` per env for log groups (`kms_key_id`) and SSM (`key_id`) |
| 1-year log retention | CKV_AWS_338 | `log_retention_days = 365` |
| Cross-region replication / DR | CKV_AWS_144 | `aws_s3_bucket_replication_configuration` to a bucket in a second region |
| Private instances | n/a | Private subnets + NAT gateway (≈ $35/month per AZ); turn off public IPs |

---

## Go-live checklist

- [ ] `make test-env ENV=prod` passes on Floci
- [ ] Image tested: `IMAGE=<your image> make test-app ENV=prod`
- [ ] `aws sts get-caller-identity` shows the **prod** account
- [ ] `backend.tfbackend` bucket renamed; `make bootstrap-state ENVS=prod` done
- [ ] ACM certificate **ISSUED**
- [ ] `bash scripts/preflight.sh prod` → OK
- [ ] ECR repo created, image pushed with the exact `docker_tag`
- [ ] Real `APP_KEY`, `DB_PASSWORD` (and other secrets) set in SSM
- [ ] Database reachable from the instance security group; migrations run
- [ ] `make plan ENV=prod` reviewed, then `make apply ENV=prod`
- [ ] All targets `healthy`; `https://<domain>/health` returns 200
- [ ] DNS record points at `alb_dns_name`
- [ ] Alarm email subscription **confirmed**
- [ ] A test release done (new `docker_tag`), and the zero-downtime roll observed
- [ ] `ami_id` and `docker_tag` committed, so prod is reproducible from git
