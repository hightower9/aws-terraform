output "sns_topic_arn" {
  value       = aws_sns_topic.alarms.arn
  description = "SNS topic all alarms publish to"
}
