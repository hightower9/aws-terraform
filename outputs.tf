output "app_url" {
  value       = "${module.alb.https_enabled ? "https" : "http"}://${module.alb.dns_name}"
  description = "Stable app URL (ALB). Point your domain at alb_dns_name."
}

output "alb_dns_name" {
  value       = module.alb.dns_name
  description = "Create a CNAME (or Route 53 alias with alb_zone_id) to this"
}

output "alb_zone_id" {
  value       = module.alb.zone_id
  description = "Hosted zone ID for a Route 53 alias record"
}

output "target_group_arn" {
  value       = module.alb.target_group_arn
  description = "Check instance health: aws elbv2 describe-target-health --target-group-arn <this>"
}

output "ecr_repository_url" {
  value       = one(module.ecr[*].repository_url)
  description = "Push the app image here, then set docker_image to it"
}

output "asg_name" {
  value       = module.ec2.asg_name
  description = "Auto Scaling Group (instances: aws autoscaling describe-auto-scaling-groups)"
}

output "ami_id" {
  value       = module.ec2.ami_id
  description = "AMI in use. Copy it into ami_id to pin it."
}

output "ssm_parameter_path" {
  value       = module.app_config.path
  description = "SSM path holding the app's env vars and secrets"
}

output "s3_bucket_name" {
  value       = module.s3.bucket_id
  description = "App storage bucket (AWS_BUCKET)"
}

output "cloudwatch_log_group" {
  value       = module.ec2.cloudwatch_log_group
  description = "Container logs: aws logs tail <group> --follow"
}

output "alarm_topic_arn" {
  value       = module.monitoring.sns_topic_arn
  description = "SNS topic receiving all alarms"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}
