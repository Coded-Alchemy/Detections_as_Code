  # ============================================
  # Terraform State Configuration
  # ============================================

terraform {
  backend "local" {
    path = "/opt/detection_as_code/terraform/state/dac.tfstate"
  }
}
