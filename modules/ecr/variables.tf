variable "project" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (local, dev, uat, prod)"
}

variable "force_delete" {
  type        = bool
  description = "Allow destroy to delete the repository even if it still holds images"
  default     = false
}

variable "keep_images" {
  type        = number
  description = "Number of most recent images to keep"
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}
