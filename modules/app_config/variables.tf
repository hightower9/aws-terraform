variable "project" {
  type        = string
  description = "Project name used for the parameter path"
}

variable "environment" {
  type        = string
  description = "Environment name used for the parameter path"
}

variable "settings" {
  type        = map(string)
  description = "Non-secret app environment variables (stored as String)"
  default     = {}
}

variable "secret_placeholders" {
  type        = map(string)
  description = "Secret names mapped to a placeholder value (stored as SecureString; real values are set out-of-band)"
  default     = {}
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
