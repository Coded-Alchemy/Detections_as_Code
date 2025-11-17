locals {
  detection_rules = {
    # Windows Defender Disabled
    windows_defender_disabled = {
      name                       = "Windows Defender Threat Detection Disabled"
      search                     = file("${path.module}/../generated/splunk/detections.spl")
      description                = "Detects when Windows Defender threat detection is disabled (EventIDs: 5001, 5010, 5012, 5101)"
      cron_schedule              = "*/5 * * * *"
      dispatch_earliest_time     = "-15m"
      dispatch_latest_time       = "now"
      alert_threshold            = "0"
      alert_digest_mode          = true
      action_email_subject       = "ALERT: Windows Defender Threat Detection Disabled"
      action_email_message_alert = <<-EOT
        Windows Defender threat detection has been disabled on one or more systems.

        Event IDs detected: 5001, 5010, 5012, or 5101

        Please investigate immediately.
      EOT
      is_scheduled               = true
      is_visible                 = true
    }

    # Suspicious PowerShell Activity
    suspicious_powershell = {
      name                      = "Suspicious PowerShell Execution"
      description               = "Detects suspicious PowerShell commands and encoded scrips"
      spl_file                  = "suspicious_powershell.spl"
      cron_schedule             = "*/10 * * * *"
      dispatch_earliest_time    = "-20m"
      dispatch_latest_time      = "now"
      alert_threshold           = "0"
      alert_severity            = "medium"
      is_scheduled               = true
      is_visible                 = true
      action_email_subject      = "ALERT: Suspicious PowerShell Activity Detected"
      action_email_message_alert = <<-EOT
        Suspicious PowerShell Activity Detected.

        This may indicate:
        - Encoded command execution
        - Download and execute attacks
        - Powershell obfuscation techniques

        Review the search results for potential malicious activity.
      EOT
    }
  }

  # Common settings
  actions           = "email"
  alert_type        = "number of events"
  alert_comparator  = "greater than"
  action_email_to   = var.alert_email
}
