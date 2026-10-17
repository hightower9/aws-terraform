output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "ID of the ALB security group"
}

output "instance_security_group_id" {
  value       = aws_security_group.instance.id
  description = "ID of the EC2 instance security group"
}
