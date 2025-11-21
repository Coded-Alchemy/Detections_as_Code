  # ============================================
  # Terraform Providers Configuration
  # ============================================


terraform {
  required_providers {
    splunk = {
      source  = "splunk/splunk"
      version = ">=1.0"
    }
  }
}

provider "splunk" {
  url                  = var.splunk_url
  insecure_skip_verify = var.insecure_skip_verify
  username             = var.splunk_username
  password             = var.splunk_password
}