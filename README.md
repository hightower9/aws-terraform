# Laravel AWS Terraform

Terraform for running a Dockerized Laravel app on AWS: highly available, zero-downtime, with HTTPS. Four environments (`local`, `dev`, `uat`, `prod`) from one configuration, and every one of them can be tested for free on your laptop with the [Floci](https://floci.io) emulator.

📘 **[Usage Guide](docs/GUIDE.md):** local testing with Floci and its web console, the environments, deploying, troubleshooting.
🚀 **[Going to Production](docs/PRODUCTION.md):** step by step from the shipped dummy values to a live HTTPS prod.

## Architecture

```
                 Internet
                    │  HTTPS 443 (ACM) · HTTP 80 → redirect
          ┌─────────▼──────────┐
          │  Application LB    │  stable DNS name · health check on /health
          └───┬────────────┬───┘
      AZ a    │            │    AZ b
   ┌──────────▼─┐      ┌───▼────────┐
   │ EC2: Docker│      │ EC2: Docker│   Auto Scaling Group (ELB health checks)
   │ Laravel app│      │ Laravel app│   no SSH: SSM Session Manager
   └─────┬──────┘      └─────┬──────┘
         └── ECR (image) · SSM Parameter Store (env + secrets) · S3 (storage)
             CloudWatch (app/boot/flow logs) · alarms → SNS → email
```

| Concern | How it's handled |
|---|---|
| **Zero-downtime deploys** | Changing `docker_tag`, `instance_type`, `ami_id` or config triggers an ASG instance refresh (min 100% / max 200%). New instances must pass the ALB health check before old ones go, and a failed rollout **auto-rolls back**. |
| **Graceful shutdown** | ALB drains for 30s, then Docker sends SIGTERM and waits 30s. |
| **High availability** | Two AZs; prod runs 2 instances (scales to 4 during a refresh). |
| **Stable URL + TLS** | ALB DNS name never changes; HTTPS with an ACM certificate, HTTP redirects. |
| **Images** | Private ECR repo per env, immutable tags, scan on push. |
| **Config & secrets** | SSM Parameter Store (`/laravel/<env>/app/*`) loaded into the container at boot. |
| **Access** | No port 22, no keys: `aws ssm start-session`. Instances only accept traffic from the ALB. |
| **Least privilege** | Instance role limited to its bucket, its log groups, its SSM path, its ECR repo. |
| **Observability** | Container logs (one stream per instance), boot logs, VPC flow logs; alarms for site down, unhealthy hosts, 5xx, CPU. |
| **State** | S3 per environment, versioned + encrypted + TLS-only, S3-native locking. |
| **Guardrails** | `make plan ENV=prod` refuses dummy values; prod destroy needs `CONFIRM=prod`; ALB deletion protection; Checkov with every exception documented. |

## Quick start (local, free)

Requires Docker, Terraform ≥ 1.10, AWS CLI v2, make and bash (Git Bash on Windows).

```bash
make start-floci            # AWS emulator (:4566) + web console (:4500)
make test-env ENV=local     # bootstrap + init + plan + apply + app health test
make floci-ui               # browse what was created
make test-all               # same for local, dev, uat and prod
```

Every environment ships with **working dummy values** (an nginx stand-in for the app, no certificate, no alarm email), so all of this works out of the box. The values that must change for real use are marked `# PLACEHOLDER` in `environments/<env>/terraform.tfvars`. See [PRODUCTION.md](docs/PRODUCTION.md).

## Environments

| | local | dev | uat | prod |
|---|---|---|---|---|
| Runs on | Floci only | Floci / AWS | Floci / AWS | Floci / AWS |
| Instance type | t3.micro | t3.small | t3.small | t3.medium |
| Instances (min/desired/max) | 1/1/2 | 1/1/2 | 1/1/2 | 2/2/4 |
| Log retention | 7d | 14d | 30d | 90d |
| Real AWS with placeholders left | n/a | warns | warns | **refused** |

## Commands

```bash
make help                              # everything below, and more
make init|plan|apply|output ENV=<env>  # real AWS (add EMULATOR=1 for Floci)
make test-env ENV=<env>                # full Floci run + app test
make test-app ENV=<env> [IMAGE=...]    # run the env's container locally like EC2 does
make destroy ENV=<env>                 # prod also needs CONFIRM=prod
make fmt | validate | security         # formatting, validation, Checkov
bash scripts/preflight.sh <env>        # which placeholders are left
```

## CI (GitHub Actions)

`.github/workflows/terraform.yml` is **manual only**: it never runs on its own. Start it from GitHub → Actions → *Terraform CI* → *Run workflow*. It runs:
- fmt, validate, preflight and Checkov (the run fails on any finding not accepted in `.checkov.yml`);
- optionally, a real `plan` for a chosen environment over GitHub OIDC (secret `AWS_ROLE_ARN`, no long-lived keys). Setup is in [PRODUCTION.md → CI access](docs/PRODUCTION.md#ci-access-github-oidc).

To make it automatic again, add a `pull_request:` trigger (see the comment in the file).

## Repository layout

```
.
├── main.tf / variables.tf / resources.tf / outputs.tf   # ONE root config for all envs
├── .terraform.lock.hcl          # provider pins (Windows, Linux, macOS)
├── environments/
│   ├── <env>/terraform.tfvars   # per-env settings (dummies marked # PLACEHOLDER)
│   ├── <env>/backend.tfbackend  # per-env state bucket
│   └── emulator.s3.tfbackend    # layered on top for EMULATOR=1 (state in Floci)
├── modules/
│   ├── vpc/             # VPC, 2 public subnets, IGW, default-SG lockdown, flow logs
│   ├── security_group/  # ALB SG (80/443) + instance SG (app port from ALB only)
│   ├── alb/             # ALB, target group + health check, HTTP/HTTPS listeners
│   ├── ec2/             # launch template, ASG + instance refresh, log groups
│   ├── ecr/             # image repository (immutable tags, scanning, lifecycle)
│   ├── app_config/      # SSM parameters: app settings + secret placeholders
│   ├── iam/             # least-privilege instance role + SSM Session Manager
│   ├── s3/              # app bucket + access-log bucket (TLS-only, KMS, versioned)
│   └── monitoring/      # SNS topic + CloudWatch alarms
├── cloud-init/user_data.sh.tpl  # boot: Docker, SSM env, ECR login, run container
├── scripts/
│   ├── bootstrap-state.sh   # create state buckets (reads backend.tfbackend)
│   ├── preflight.sh         # block real prod plans with placeholders left
│   ├── start-floci.sh       # start Floci + console
│   ├── test-app.sh          # run an env's container locally + health check
│   └── start-localstack.sh  # legacy alternative
├── docker-compose.floci.yml # Floci 2.1.0 + Floci UI 0.5.0 (bound to 127.0.0.1)
├── .checkov.yml             # security scan config + documented accepted risks
├── .github/workflows/terraform.yml  # manual-only CI
├── docs/GUIDE.md · docs/PRODUCTION.md
└── Makefile
```

## Not included

- **Database:** Laravel needs one. Use RDS/Aurora or an existing DB and pass the connection via SSM. See [PRODUCTION.md → Database](docs/PRODUCTION.md#database).
- **Optional hardening** (WAF, ALB access logs, customer KMS keys, cross-region replication, private subnets + NAT): documented in [PRODUCTION.md → Optional hardening](docs/PRODUCTION.md#optional-hardening).
