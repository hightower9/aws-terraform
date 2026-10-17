# All alarms notify this topic. Subscribe more endpoints (Slack via
# AWS Chatbot, PagerDuty, ...) to it outside Terraform or add them here.
resource "aws_sns_topic" "alarms" {
  name              = "${var.project}-${var.environment}-alarms"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alarms"
  })
}

# Email subscriptions must be confirmed from the inbox before they deliver.
resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  actions = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project}-${var.environment}-cpu-high"
  alarm_description   = "Average CPU across the ASG above ${var.cpu_threshold}% for 10 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project}-${var.environment}-unhealthy-hosts"
  alarm_description   = "At least one instance is failing the ALB health check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  alarm_name          = "${var.project}-${var.environment}-no-healthy-hosts"
  alarm_description   = "No healthy instances behind the ALB: the site is down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project}-${var.environment}-app-5xx"
  alarm_description   = "The app returned more than ${var.error_5xx_threshold} 5xx responses in 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_5xx_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${var.project}-${var.environment}-alb-5xx"
  alarm_description   = "The ALB itself returned more than ${var.error_5xx_threshold} 5xx responses in 5 minutes (no healthy targets, timeouts)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_5xx_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = var.tags
}
