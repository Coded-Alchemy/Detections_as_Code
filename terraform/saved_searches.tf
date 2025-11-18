# ============================================
# Splunk Saved Searches (Detection Rules)
# ============================================
# This resource automatically creates a saved search in Splunk
# for each rule defined in locals.tf
#
# The for_each loop iterates over local.detection_rules
# and creates one splunk_saved_searches resource per rule

resource "splunk_saved_searches" "detections" {
  # Create one resource for each detection rule
  for_each = local.detection_rules

  # Basic information
  name        = each.value.name
  description = each.value.description

  # The SPL search query - reads from generated file
  search = file("${path.module}/../generated/splunk/${each.value.spl_file}")

  # ============================================
  # Schedule Configuration
  # ============================================
  cron_schedule          = each.value.cron_schedule
  dispatch_earliest_time = each.value.dispatch_earliest_time
  dispatch_latest_time   = each.value.dispatch_latest_time

  # ============================================
  # Alert Configuration
  # ============================================
  alert_type       = local.alert_type
  alert_comparator = local.alert_comparator
  alert_threshold  = each.value.alert_threshold
  alert_digest_mode = true  # Group multiple alerts together

  # ============================================
  # Email Alert Action
  # ============================================
  actions                    = local.actions
  action_email_to            = var.alert_email
  action_email_subject       = each.value.alert_email_subject
  action_email_message_alert = each.value.alert_email_message

  # ============================================
  # Enable and Priority Settings
  # ============================================
  is_scheduled = true
  is_visible   = true

  # Set priority based on severity
  schedule_priority = each.value.alert_severity == "critical" || each.value.alert_severity == "high" ? "highest" : "default"

  # ============================================
  # Metadata (optional but helpful)
  # ============================================
  # Add labels to help organize searches in Splunk UI
  # These show up as tags in Splunk
}