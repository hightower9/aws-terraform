output "asg_name" {
  value       = aws_autoscaling_group.this.name
  description = "Name of the Auto Scaling Group"
}

output "asg_arn" {
  value       = aws_autoscaling_group.this.arn
  description = "ARN of the Auto Scaling Group"
}

output "launch_template_id" {
  value       = aws_launch_template.this.id
  description = "ID of the launch template"
}

output "launch_template_latest_version" {
  value       = aws_launch_template.this.latest_version
  description = "Latest version of the launch template"
}

output "ami_id" {
  value       = local.ami_id
  description = "AMI the instances run (pin it via ami_id in prod)"
}

output "cloudwatch_log_group" {
  value       = aws_cloudwatch_log_group.app.name
  description = "CloudWatch log group for application logs"
}
