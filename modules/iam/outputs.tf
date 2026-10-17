output "instance_profile_name" {
  value       = aws_iam_instance_profile.this.name
  description = "Name of the EC2 instance profile"

  # Instances need their permissions (SSM, ECR, logs) the moment they boot.
  depends_on = [aws_iam_role_policy.ec2_inline, aws_iam_role_policy_attachment.ssm_core]
}

output "instance_profile_arn" {
  value       = aws_iam_instance_profile.this.arn
  description = "ARN of the EC2 instance profile"
}

output "role_arn" {
  value       = aws_iam_role.ec2.arn
  description = "ARN of the EC2 IAM role"
}
