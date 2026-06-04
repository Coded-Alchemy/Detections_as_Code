# ============================================
# Terraform State Configuration
# ============================================

terraform {
  backend "local" {
    path = "/opt/detection_as_code/terraform/state/dac.tfstate"
  }
  required_providers {
    splunk = {
      source  = "splunk/splunk"
      version = "1.4.32"
    }
  }
}
