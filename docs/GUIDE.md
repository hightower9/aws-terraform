# Usage Guide

How to run this repo day to day: testing locally on the Floci emulator (with its web console), deploying each environment, and moving a change from `local` through `dev` and `uat` to `prod`.

> Taking an environment live for real (certificate, image, secrets, DNS)? Follow **[PRODUCTION.md](PRODUCTION.md)**.

- [1. Concepts in 60 seconds](#1-concepts-in-60-seconds)
- [2. One-time setup](#2-one-time-setup)
- [3. The environments](#3-the-environments)
- [4. Testing locally with Floci](#4-testing-locally-with-floci)
- [5. Testing your Docker image](#5-testing-your-docker-image)
- [6. Deploying to real AWS](#6-deploying-to-real-aws)
- [7. Promoting a change: local → dev → uat → prod](#7-promoting-a-change-local--dev--uat--prod)
- [8. Changing settings per environment](#8-changing-settings-per-environment)
- [9. Cleaning up](#9-cleaning-up)
- [10. Troubleshooting](#10-troubleshooting)
- [Command cheat sheet](#command-cheat-sheet)

---

## 1. Concepts in 60 seconds

Every command has the form:

```bash
make <target> ENV=<local|dev|uat|prod> [EMULATOR=1] [TF_ARGS='-var k=v']
```

- **One Terraform config, four environments.** The `.tf` files at the repo root are shared. An environment is just two files:
  - `environments/<env>/terraform.tfvars` holds its settings.
  - `environments/<env>/backend.tfbackend` says where its state lives (an S3 bucket).
- **Floci** is a free AWS emulator running in Docker on `localhost:4566`, with a web console on `localhost:4500`. Nothing you do there costs money or touches AWS.
- **`EMULATOR=1`** runs an environment's *real* settings against Floci. Leave it off and you are on **real AWS**. `local` always uses Floci.
- **Dummy values** are marked `# PLACEHOLDER` in the tfvars. Everything works on Floci as shipped. Before a real prod deploy you replace those values, and `make plan ENV=prod` refuses to run until you do.

| You type | Talks to | State stored in |
|---|---|---|
| `make plan ENV=local` | Floci (always) | `laravel-tf-state-local` bucket **in Floci** |
| `make plan ENV=dev EMULATOR=1` | Floci | `laravel-tf-state-dev` bucket **in Floci** |
| `make plan ENV=dev` | **Real AWS** | `laravel-tf-state-dev` bucket in your AWS account |

Each environment and mode gets its own working folder (`.terraform-envs/<env>` or `.terraform-envs/<env>-emulator`), so switching never needs a re-init and can't mix up state. The workflow is always **init → plan → apply**, and `apply` only applies the plan you just reviewed.

### What gets built (per environment)

```
Internet ─► ALB (stable DNS, HTTPS when a cert is set, health checks)
              ├─► EC2 in AZ a ─┐  Auto Scaling Group, ELB health checks,
              └─► EC2 in AZ b ─┘  zero-downtime instance refresh + auto-rollback
                    │
                    ├─ app container (image from ECR, env vars from SSM Parameter Store)
                    ├─ S3 app bucket (+ access-log bucket)
                    └─ CloudWatch logs · VPC flow logs · alarms → SNS (email)
```

Instances only accept traffic from the ALB. There is no SSH; shell access goes through SSM Session Manager.

---

## 2. One-time setup

### Tools

| Tool | Needed for | Check |
|---|---|---|
| Terraform ≥ 1.10 | everything | `terraform version` |
| GNU Make | everything | `make --version` |
| Docker Desktop (running) | Floci, the console, app tests | `docker version` |
| AWS CLI v2 | bootstrap, real AWS, app test config | `aws --version` |
| bash | Makefile + scripts | on Windows use **Git Bash** |

> **Windows:** run every `make` command from **Git Bash**, not PowerShell or cmd.

### Optional `.env`

```bash
cp .env.example .env    # set AWS_PROFILE / AWS_REGION for real-AWS runs
```

Don't put `AWS_ENDPOINT_URL` in `.env`. It would send real runs to the emulator.

### Start Floci

```bash
make start-floci
```

This starts `floci/floci:2.1.0` (AWS emulator, `:4566`) and **Floci UI** (`:4500`) via `docker-compose.floci.yml`. Data is kept in `.floci/` across restarts.

---

## 3. The environments

All four use the same Terraform code. They differ only in their tfvars:

| | local | dev | uat | prod |
|---|---|---|---|---|
| Purpose | Emulator sandbox | Development | Production-like testing | Production |
| Runs on | Floci only | Floci or AWS | Floci or AWS | Floci or AWS |
| Instance type | t3.micro | t3.small | t3.small | t3.medium |
| Instances (min/desired/max) | 1/1/2 | 1/1/2 | 1/1/2 | **2/2/4** |
| VPC CIDR | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 | 10.40.0.0/16 |
| Image (as shipped) | `nginx:1.27-alpine` | stand-in, PLACEHOLDER | stand-in, PLACEHOLDER | stand-in, PLACEHOLDER |
| HTTPS certificate | none | optional | PLACEHOLDER | PLACEHOLDER (required) |
| Pinned AMI | latest | latest | PLACEHOLDER | PLACEHOLDER (required) |
| Log retention | 7 days | 14 days | 30 days | 90 days |
| ALB deletion protection | off | off | off | **on** (off on Floci) |
| Destroy deletes non-empty buckets | yes | yes | no | no (enforced) |
| Placeholders left | n/a | warning | warning | **plan refused** |

All environments run in us-east-1a and us-east-1b with non-overlapping CIDRs.

---

## 4. Testing locally with Floci

Make sure Floci is running (`make start-floci`).

### 4a. One command per environment

```bash
make test-env ENV=local    # bootstrap state + init + plan + apply + output + app test
make test-env ENV=dev
make test-env ENV=uat
make test-env ENV=prod     # prod's real settings, on the emulator
make test-all              # all four, stops at the first failure
```

### 4b. Step by step

```bash
make bootstrap-state EMULATOR=1     # once: creates the state buckets in Floci
make init   ENV=uat EMULATOR=1
make plan   ENV=uat EMULATOR=1      # review the plan
make apply  ENV=uat EMULATOR=1
make output ENV=uat EMULATOR=1      # app_url, ecr_repository_url, ssm_parameter_path, ...
```

`local` needs no `EMULATOR=1`. The shortcut forms work too: `make plan-uat EMULATOR=1`.

### 4c. Looking around with the AWS CLI

```bash
export AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
aws elbv2 describe-load-balancers --query 'LoadBalancers[].DNSName'
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].[AutoScalingGroupName,HealthCheckType]'
aws autoscaling describe-instance-refreshes --auto-scaling-group-name <asg_name>
MSYS_NO_PATHCONV=1 aws ssm get-parameters-by-path --path /laravel/dev/app --with-decryption \
  --query 'Parameters[].[Name,Value]' --output table
unset AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY   # before any real-AWS work!
```

(`MSYS_NO_PATHCONV=1` stops Git Bash on Windows from rewriting `/laravel/...` into a Windows path.)

### 4d. Seeing it in the Floci UI

Open **http://localhost:4500** (`make floci-ui`). The console shows what Terraform actually created, so you can connect each `plan` line to a real resource:

| Console section | What you'll see from this repo |
|---|---|
| **Compute** | Per env: the ASG instances (`laravel-<env>-asg`) with type, AZ and status. Replaced ones show as `terminated` after a refresh. |
| **Networking** | `laravel-<env>-vpc` for each env applied, next to Floci's default VPC |
| **Load Balancing** | `laravel-<env>` ALBs and their target groups |
| **Storage** | `laravel-<env>-storage-…` and `-s3-logs-…` buckets, plus the `laravel-tf-state-<env>` state buckets |
| **Parameters** | `/laravel/<env>/app/*`: the env vars and secrets the container receives |
| **CloudWatch Logs** | `/ec2/laravel/<env>/app`, `/cloud-init`, `/vpc/laravel/<env>/flow-logs` |

Ways to use it:
- **Compare environments:** apply two envs and they appear side by side, each with its own VPC, ALB and buckets.
- **Watch a rolling deploy:** `make plan ENV=dev EMULATOR=1 TF_ARGS='-var docker_tag=1.27.4-alpine'`, then `make apply ENV=dev EMULATOR=1`, then refresh **Compute**.
- **Check a destroy:** after `make destroy ENV=<env> EMULATOR=1` that environment's resources disappear.

The console has no login, so it and Floci are bound to `127.0.0.1` only. This console version doesn't list IAM roles; use `aws iam list-roles` (4c).

### What Floci does and doesn't prove

| ✅ Proves | ❌ Does not prove |
|---|---|
| Every env's config plans and applies cleanly | Real IAM permission enforcement |
| Module wiring (IDs, ARNs, SG references, SSM paths) | That the ALB really routes traffic to healthy instances |
| A `docker_tag` / config change starts an instance refresh with the right zero-downtime settings | That the refresh waits for health and rolls back (AWS behaviour) |
| State buckets + S3 lockfile locking work | Certificates, DNS, quotas, AMI availability in your account |

On Floci the EC2 "instances" are containers, so cloud-init can't run Docker inside them and their ALB targets stay `unhealthy`. That's expected. `make test-app` (section 5) tests the app container itself. Keep a real-AWS dev deploy as the final check.

---

## 5. Testing your Docker image

`make test-app` runs an environment's image **exactly as cloud-init runs it on EC2**:
- the same port mapping and health check;
- if Floci is running and the env has been applied, the **same env vars, loaded from that env's SSM path**.

```bash
make test-app ENV=local                    # nginx stand-in, should PASS
```

Testing your Laravel image:

```bash
docker build -t laravel-app:dev /path/to/your/laravel-app
IMAGE=laravel-app:dev make test-app ENV=dev
IMAGE=laravel-app:dev make test-app ENV=prod    # with prod's ports, health path and SSM settings
```

> With the shipped placeholders the env expects nginx (`container_port = 80`, `health_check_url = "/"`). For a Laravel image, set `container_port = 8000` and `health_check_url = "/health"` (or `/up`) in that env's tfvars first.

| Variable | Effect | Example |
|---|---|---|
| `IMAGE` | Test a different image/tag | `IMAGE=laravel-app:feature-x make test-app ENV=dev` |
| `PORT` | Use another host port (if 8000 is busy) | `PORT=8081 make test-app ENV=dev` |
| `KEEP=1` | Leave the container running afterwards | `KEEP=1 make test-app ENV=dev`, then open `http://localhost:8000` |

The output is `PASS: [dev] app healthy at ... after Ns`, or `FAIL:` followed by the container's last 50 log lines. The exit code is non-zero on failure.

---

## 6. Deploying to real AWS

Leave out `EMULATOR=1`. **This costs money.** For a first real deploy of uat or prod, follow [PRODUCTION.md](PRODUCTION.md). The short version for dev, which works as shipped with the nginx stand-in:

```bash
export AWS_PROFILE=laravel-dev && aws sts get-caller-identity   # confirm the account
make bootstrap-state ENVS=dev        # once per account: creates the state bucket
make init  ENV=dev
make plan  ENV=dev                   # preflight lists placeholders as warnings; READ the plan
make apply ENV=dev
make output ENV=dev                  # app_url = http://<alb-dns-name>
```

The account ID is detected by Terraform itself; there's nothing to pass.

### Releasing a new version

Change `docker_tag` (or `instance_type`, `ami_id`, ...), then `make plan` and `make apply`. That starts a **rolling instance refresh**:
- New instances launch first, and must pass the ALB health check before old ones are terminated.
- If they never get healthy, AWS rolls back automatically.
- `apply` returns when the refresh starts. Follow it with `aws autoscaling describe-instance-refreshes --auto-scaling-group-name <asg_name>`.

---

## 7. Promoting a change: local → dev → uat → prod

```bash
# 0. Static checks
make fmt && make validate && make security     # security = Checkov (pip install checkov)

# 1. Every environment on the emulator
make test-all

# 2. The app image with each environment's settings
IMAGE=laravel-app:<tag> make test-app ENV=uat
IMAGE=laravel-app:<tag> make test-app ENV=prod

# 3. Real AWS, one environment at a time, reading each plan
AWS_PROFILE=laravel-dev  make init ENV=dev  && AWS_PROFILE=laravel-dev  make plan ENV=dev  && AWS_PROFILE=laravel-dev  make apply ENV=dev
AWS_PROFILE=laravel-uat  make init ENV=uat  && AWS_PROFILE=laravel-uat  make plan ENV=uat  && AWS_PROFILE=laravel-uat  make apply ENV=uat
AWS_PROFILE=laravel-prod make init ENV=prod && AWS_PROFILE=laravel-prod make plan ENV=prod && AWS_PROFILE=laravel-prod make apply ENV=prod
```

Run step 3 one line at a time and read each plan before applying. The GitHub Actions workflow can run steps 0 and a real plan for you, but **only when started by hand** (GitHub → Actions → *Terraform CI* → *Run workflow*).

---

## 8. Changing settings per environment

| What | Where | Example |
|---|---|---|
| Infrastructure settings | `environments/<env>/terraform.tfvars` | `instance_type = "t3.large"` |
| App env vars (non-secret) | `app_settings` in tfvars, stored in SSM | `app_settings = { DB_HOST = "..." }` |
| App secrets | SSM, set by hand (never in git) | `aws ssm put-parameter --overwrite --type SecureString --name /laravel/prod/app/APP_KEY --value ...` |
| Personal / secret overrides (git-ignored) | `environments/<env>/secrets.auto.tfvars` | n/a |
| One-off override for a single run | `TF_ARGS` on `plan` | `make plan ENV=uat TF_ARGS='-var docker_tag=v1.4.2'` |

`TF_VAR_<name>` environment variables do **not** override values that are in tfvars. Use `TF_ARGS`.

Commonly changed variables (full list with descriptions: `variables.tf`):

| Variable | Meaning |
|---|---|
| `docker_image`, `docker_tag` | Image the instances run. Use the ECR URL and an immutable tag. |
| `container_port`, `health_check_url` | Where the app listens and what the ALB polls |
| `instance_type`, `ami_id` | Instance size and pinned OS image (changes roll with zero downtime) |
| `asg_min_size` / `asg_desired_capacity` / `asg_max_size` | Instance count. Keep max ≥ 2 × desired. |
| `acm_certificate_arn` | Enables HTTPS (and HTTP→HTTPS redirect) |
| `allowed_ingress_cidrs` | Who can reach the ALB |
| `alarm_email` | Who gets alarms |
| `log_retention_days` | CloudWatch retention |

---

## 9. Cleaning up

```bash
# Emulator
make destroy ENV=local
make destroy ENV=prod EMULATOR=1         # deletion protection is off on Floci
make stop-floci                           # stop Floci + console, keep data in .floci/
rm -rf .floci                             # full emulator reset (then bootstrap-state EMULATOR=1 again)

# Real AWS
make destroy ENV=dev
# prod: see PRODUCTION.md → "Tear down prod" (deletion protection + CONFIRM=prod)
```

`make clean` only deletes the local `.terraform-envs/` working folders. State lives in S3, so nothing is lost; just `make init` again.

---

## 10. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `failed to connect to the docker API` | Docker Desktop isn't running. Start it, then `make start-floci`. |
| `Floci did not become ready within 60s` | Check `docker logs floci`. Port 4566 may already be used (e.g. by LocalStack). |
| Floci UI page won't load | `docker logs floci-ui`. Port 4500 may be in use. Restart: `make stop-floci && make start-floci`. |
| `ENV must be one of: local dev uat prod` | Typo in `ENV=`. |
| `preflight [prod]: refusing to plan` | Placeholders are left in prod's tfvars or backend file. Replace them; see [PRODUCTION.md](PRODUCTION.md). |
| `No plan for dev — run 'make plan ...' first` | Run `plan` before `apply`, with the same `EMULATOR` setting. |
| `Backend initialization required` / `Backend configuration changed` | Run `make init ENV=<env>` (with `EMULATOR=1` if that's the mode you're in). |
| `NoSuchBucket` during init | The state bucket doesn't exist yet: `make bootstrap-state ENVS=<env>` (add `EMULATOR=1` for Floci). |
| `No valid credential sources found` | Real-AWS mode without AWS credentials. Log in, or add `EMULATOR=1`. |
| `pull access denied for laravel-app` | That image isn't in a registry or built locally. `docker build -t laravel-app:<tag> .` or use `IMAGE=`. |
| `FAIL: container exited` | The app crashed on start. Output shows its logs; try `KEEP=1`, then `docker logs laravel-<env>-app-test`. |
| `FAIL: app never became healthy` | Nothing answered 2xx at `container_port` + `health_check_url`. Check both against your image. |
| `port is already allocated` | Another container is using the host port. `PORT=8081 make test-app ENV=<env>`. |
| A Floci plan always shows the instance profile / flow log tags changing | Floci quirk: it doesn't store those tags. Harmless; real AWS plans are clean. |
| Real AWS: instance refresh `Cancelled` / `RollbackSuccessful` | The new instances never passed the ALB health check. Check `/ec2/laravel/<env>/cloud-init` and `/app` logs. |
| Real AWS: `Error acquiring the state lock` | Another run is in progress, or one crashed. If you're sure nothing is running: `TF_DATA_DIR=.terraform-envs/<env> terraform force-unlock <LOCK_ID>`. |

---

## Command cheat sheet

```bash
# Emulator
make start-floci | stop-floci | floci-ui          # console: http://localhost:4500
make test-env ENV=<env> | test-all                # full emulator runs + app test
make bootstrap-state EMULATOR=1                   # once
make init|plan|apply|output|destroy ENV=<env> EMULATOR=1
make test-app ENV=<env> [IMAGE=..] [PORT=..] [KEEP=1]

# Real AWS
make bootstrap-state ENVS=<env>                   # once per account
make init|plan|apply|output ENV=<env>
make plan ENV=<env> TF_ARGS='-var docker_tag=3f9c2ab'   # one-off override
make destroy ENV=<env>                            # prod: CONFIRM=prod (see PRODUCTION.md)

# Checks
make fmt | validate | security | help
bash scripts/preflight.sh <env>                   # what's still a placeholder
```
