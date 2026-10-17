locals {
  https_enabled = var.certificate_arn != ""
}

resource "aws_lb" "this" {
  name               = substr("${var.project}-${var.environment}", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alb"
  })
}

# The ALB health check is what gates deploys: the ASG uses ELB health, so
# an instance refresh only retires the old instance once the new one
# answers health_check_path with a 2xx/3xx.
resource "aws_lb_target_group" "app" {
  name_prefix          = "app-"
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-app-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Without a certificate (local/dev placeholders) HTTP forwards to the app.
# With one, HTTP permanently redirects to HTTPS.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.https_enabled ? "redirect" : "forward"
    target_group_arn = local.https_enabled ? null : aws_lb_target_group.app.arn

    dynamic "redirect" {
      for_each = local.https_enabled ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = var.tags
}
