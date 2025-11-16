variable "splunk_url" {
  description = "Splunk instance URL"
  type        = string
}

variable "splunk_username" {
  description = "Splunk admin username"
  type        = string
  sensitive   = true
}

variable "splunk_password" {
  description = "Splunk admin password"
  type        = string
  sensitive   = true
}

variable "insecure_skip_verify" {
  description = "Skip SSL certificate verification"
  type        = bool
  default     = false
}