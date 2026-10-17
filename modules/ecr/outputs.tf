output "repository_url" {
  value       = aws_ecr_repository.this.repository_url
  description = "Push the app image here; set docker_image to this value"
}

output "repository_arn" {
  value       = aws_ecr_repository.this.arn
  description = "ARN of the ECR repository"
}
