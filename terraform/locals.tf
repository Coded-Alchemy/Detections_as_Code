# ============================================
# Detection Rules Configuration
# ============================================
# Add new rules by creating a new block below
# Each key should match the Sigma rule filename (without .yml)

locals {

  detection_rules = {

    # Rule 1: Windows Defender Disabled
    windows_defender_disabled = {
      name        = "Windows Defender Threat Detection Disabled"
      description = "Detects when Windows Defender threat detection is disabled (EventIDs: 5001, 5010, 5012, 5101)"
      spl_file    = "windows_defender_disabled.spl"

      # Schedule: How often to run the search
      cron_schedule          = "*/5 * * * *" # Every 5 minutes
      dispatch_earliest_time = "-15m"        # Look back 15 minutes
      dispatch_latest_time   = "now"         # Until now

      # Alert settings
      alert_threshold = "0"    # Alert if ANY events found
      alert_severity  = "high" # Priority level

      # Email configuration
      alert_email_subject = "ALERT: Windows Defender Threat Detection Disabled"
      alert_email_message = <<-EOT
        Windows Defender threat detection has been disabled on one or more systems.

        Event IDs detected: 5001, 5010, 5012, or 5101

        Action Required:
        - Investigate which system(s) are affected
        - Determine if this was authorized
        - Re-enable Windows Defender if unauthorized
        - Check for malware or compromise

        Please investigate immediately.
      EOT
    }

    # Rule 2: Suspicious PowerShell
    suspicious_powershell = {
      name        = "Suspicious PowerShell Execution"
      description = "Detects suspicious PowerShell commands and encoded scripts"
      spl_file    = "suspicious_powershell.spl"

      # Schedule
      cron_schedule          = "*/10 * * * *" # Every 10 minutes
      dispatch_earliest_time = "-20m"         # Look back 20 minutes
      dispatch_latest_time   = "now"

      # Alert settings
      alert_threshold = "0"
      alert_severity  = "medium"

      # Email configuration
      alert_email_subject = "ALERT: Suspicious PowerShell Activity Detected"
      alert_email_message = <<-EOT
        Suspicious PowerShell execution detected.

        This may indicate:
        - Encoded command execution
        - Download and execute attacks
        - PowerShell obfuscation techniques
        - Living off the land (LOL) attacks

        Action Required:
        - Review the PowerShell commands in search results
        - Identify the user and system
        - Determine if activity is authorized
        - Investigate for signs of compromise
      EOT
    }

    # Rule 3: Failed Login Attempts
    failed_login_attempts = {
      name        = "Excessive Failed Login Attempts"
      description = "Detects multiple failed login attempts indicating potential brute force attack"
      spl_file    = "failed_login_attempts.spl"

      # Schedule
      cron_schedule          = "*/15 * * * *" # Every 15 minutes
      dispatch_earliest_time = "-30m"         # Look back 30 minutes
      dispatch_latest_time   = "now"

      # Alert settings
      alert_threshold = "5" # Alert if MORE than 5 failed attempts
      alert_severity  = "high"

      # Email configuration
      alert_email_subject = "ALERT: Brute Force Attack Detected"
      alert_email_message = <<-EOT
        Multiple failed login attempts detected, indicating a possible brute force attack.

        Action Required:
        - Review source IPs in the search results
        - Check for successful logins from same source
        - Consider blocking offending IPs at firewall
        - Verify user accounts are not compromised
        - Enable account lockout policies if not present

        This alert triggers when more than 5 failed login attempts occur within 30 minutes.
      EOT
    }

    # ============================================
    # ADD NEW RULES BELOW THIS LINE
    # ============================================
    # Template for adding a new rule:
    #
    # rule_name = {
    #   name        = "Rule Display Name"
    #   description = "What this rule detects"
    #   spl_file    = "rule_name.spl"
    #
    #   cron_schedule          = "*/10 * * * *"
    #   dispatch_earliest_time = "-20m"
    #   dispatch_latest_time   = "now"
    #
    #   alert_threshold = "0"
    #   alert_severity  = "medium"
    #
    #   alert_email_subject = "ALERT: Your Alert Subject"
    #   alert_email_message = <<-EOT
    #     Your detailed alert message here.
    #     Can span multiple lines.
    #   EOT
    # }

  }

  # ============================================
  # Common Alert Settings
  # ============================================
  # These apply to ALL detection rules

  actions          = "email"
  alert_type       = "number of events"
  alert_comparator = "greater than"

  # Create a simple map for severity lookups
  severity_map = {
    for key, rule in local.detection_rules : key => rule.alert_severity
  }

  # ============================================
  # Cron Schedule Examples (for reference)
  # ============================================
  # */5 * * * *    = Every 5 minutes
  # */10 * * * *   = Every 10 minutes
  # */15 * * * *   = Every 15 minutes
  # */30 * * * *   = Every 30 minutes
  # 0 * * * *      = Every hour
  # 0 */2 * * *    = Every 2 hours
  # 0 0 * * *      = Once per day at midnight

  # ============================================
  # Time Window Examples (for reference)
  # ============================================
  # -5m   = Last 5 minutes
  # -15m  = Last 15 minutes
  # -30m  = Last 30 minutes
  # -1h   = Last 1 hour
  # -4h   = Last 4 hours
  # -24h  = Last 24 hours
  # -7d   = Last 7 days
}