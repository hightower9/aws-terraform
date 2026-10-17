output "bucket_id" {
  value       = aws_s3_bucket.this.id
  description = "ID of the app storage bucket"
}

output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "ARN of the app storage bucket"
}

output "bucket_domain_name" {
  value       = aws_s3_bucket.this.bucket_domain_name
  description = "Domain name of the app storage bucket"
}

output "logs_bucket_id" {
  value       = aws_s3_bucket.logs.id
  description = "ID of the S3 access logs bucket"
}

output "logs_bucket_arn" {
  value       = aws_s3_bucket.logs.arn
  description = "ARN of the S3 access logs bucket"
}
