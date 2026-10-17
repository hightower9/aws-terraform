output "dns_name" {
  value       = aws_lb.this.dns_name
  description = "Stable public DNS name of the ALB (point your domain's CNAME/alias here)"
}

output "zone_id" {
  value       = aws_lb.this.zone_id
  description = "Hosted zone ID of the ALB, for Route 53 alias records"
}

output "arn_suffix" {
  value       = aws_lb.this.arn_suffix
  description = "ALB ARN suffix (CloudWatch metric dimension)"
}

output "target_group_arn" {
  value       = aws_lb_target_group.app.arn
  description = "Target group the ASG registers instances in"
}

output "target_group_arn_suffix" {
  value       = aws_lb_target_group.app.arn_suffix
  description = "Target group ARN suffix (CloudWatch metric dimension)"
}

output "https_enabled" {
  value       = local.https_enabled
  description = "Whether an HTTPS listener is configured"
}
