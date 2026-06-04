# ============================================
# Terraform Providers Configuration
# ============================================

provider "splunk" {
  url                  = var.splunk_url
  insecure_skip_verify = var.insecure_skip_verify
  username             = var.splunk_username
  password             = var.splunk_password
}