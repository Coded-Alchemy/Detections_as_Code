resource "splunk_saved_searches" "windows_defender_disabled" {
  name                       = "Windows Defender Threat Detection Disabled"
  search                     = file("${path.module}/../generated/splunk/detections.spl")
  description                = "Detects when Windows Defender threat detection is disabled (EventIDs: 5001, 5010, 5012, 5101)"
  cron_schedule              = "*/5 * * * *"
  dispatch_earliest_time     = "-15m"
  dispatch_latest_time       = "now"
  alert_type                 = "number of events"
  alert_comparator           = "greater than"
  alert_threshold            = "0"
  alert_digest_mode          = true
  actions                    = "email"
  action_email_to            = var.alert_email
  action_email_subject       = "ALERT: Windows Defender Threat Detection Disabled"
  action_email_message_alert = <<-EOT
    Windows Defender threat detection has been disabled on one or more systems.

    Event IDs detected: 5001, 5010, 5012, or 5101

    Please investigate immediately.
  EOT
  is_scheduled               = true
  is_visible                 = true
}