output "path" {
  value       = local.path
  description = "SSM path holding the app's environment variables"

  # Consumers (the instances) must not boot before their config exists.
  depends_on = [aws_ssm_parameter.settings, aws_ssm_parameter.secrets]
}
