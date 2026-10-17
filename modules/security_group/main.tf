# -------- ALB: the only thing reachable from the internet --------
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "Public entry point for the Laravel app"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP (redirected to HTTPS when a certificate is set)"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.instance.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  description                  = "Forward to app instances"
}

# -------- Instances: only the ALB may connect; no SSH (use SSM) --------
resource "aws_security_group" "instance" {
  name        = "${var.project}-${var.environment}-ec2-sg"
  description = "Laravel EC2 instances (traffic from the ALB only)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ec2-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "instance_from_alb" {
  security_group_id            = aws_security_group.instance.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  description                  = "App port from the ALB"
}

# Outbound: image pulls, AWS APIs (SSM, ECR, S3, CloudWatch), OS packages.
resource "aws_vpc_security_group_egress_rule" "instance_all" {
  security_group_id = aws_security_group.instance.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic"
}
