data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  # Pin ami_id in prod so a newly published AMI never triggers an
  # unplanned rolling replacement; empty = latest Amazon Linux 2023.
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux.id

  user_data = templatefile("${path.module}/../../cloud-init/user_data.sh.tpl", {
    docker_image       = var.docker_image
    docker_tag         = var.docker_tag
    app_port           = var.app_port
    container_port     = var.container_port
    app_name           = var.project
    environment        = var.environment
    aws_region         = var.aws_region
    container_name     = "${var.project}-${var.environment}-app"
    health_check_url   = var.health_check_url
    startup_timeout    = var.startup_timeout
    ssm_parameter_path = var.ssm_parameter_path
    app_log_group      = aws_cloudwatch_log_group.app.name
    cloud_init_group   = aws_cloudwatch_log_group.cloud_init.name
  })
}

# -------- Launch Template: definition of the desired instance --------
resource "aws_launch_template" "this" {
  name_prefix   = "${var.project}-${var.environment}-"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.security_group_id]

  user_data = base64encode(local.user_data)

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type = "gp3"
      volume_size = var.root_volume_size
      encrypted   = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name = "${var.project}-${var.environment}-ec2"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(var.tags, {
      Name = "${var.project}-${var.environment}-volume"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-launch-template"
  })
}

# -------- Auto Scaling Group behind the ALB --------
resource "aws_autoscaling_group" "this" {
  name_prefix = "${var.project}-${var.environment}-"

  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [var.target_group_arn]

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  # A pinned version (not "$Latest") is what lets Terraform see a template
  # change and trigger the instance_refresh below.
  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # ELB health = the app's health_check_url via the ALB, not just "VM is up".
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  # Rolling replacement on any launch-template change (instance_type, AMI,
  # user_data / docker_tag, disk). max 200% / min 100% means the new
  # instance is launched and must pass the ALB health check BEFORE the old
  # one is terminated; if it never gets healthy the refresh rolls back.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = var.health_check_grace_period
      auto_rollback          = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

  lifecycle {
    # Capacity may be changed by hand during an incident; don't fight it.
    ignore_changes = [desired_capacity]

    precondition {
      condition     = var.asg_max_size >= 2 * var.asg_desired_capacity
      error_message = "asg_max_size must be at least 2x asg_desired_capacity so a refresh can launch replacements before terminating old instances."
    }
  }
}

# -------- CloudWatch log groups (created here so they get retention) --------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ec2/${var.project}/${var.environment}/app"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-app-logs"
  })
}

resource "aws_cloudwatch_log_group" "cloud_init" {
  name              = "/ec2/${var.project}/${var.environment}/cloud-init"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-cloud-init-logs"
  })
}
