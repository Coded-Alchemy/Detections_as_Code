variable "splunk_url" {}
variable "splunk_username" {}
variable "splunk_password" {
  sensitive = true
}