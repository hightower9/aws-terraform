output "vpc_id" {
  value       = aws_vpc.this.id
  description = "ID of the created VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "IDs of the public subnets (one per AZ)"
}

output "internet_gateway_id" {
  value       = aws_internet_gateway.this.id
  description = "ID of the internet gateway"
}
