# ============================================
# Outputs for Deployed Detection Rules
# ============================================

output "deployed_detections" {
  description = "Map of all deployed detection rules with details"
  value = {
    for key, search in splunk_saved_searches.detections : key => {
      name        = search.name
      id          = search.id
      description = search.description
      severity    = local.detection_rules[key].alert_severity
      schedule    = local.detection_rules[key].cron_schedule
    }
  }
}

output "detection_count" {
  description = "Total number of detection rules deployed"
  value       = length(keys(splunk_saved_searches.detections))
}

output "detection_names" {
  description = "List of all deployed detection rule names"
  value       = [for key, search in splunk_saved_searches.detections : search.name]
}

output "high_severity_count" {
  description = "Number of high severity rules"
  value = length([
    for key, rule in local.detection_rules : key
    if rule.alert_severity == "high"
  ])
}

output "critical_severity_count" {
  description = "Number of critical severity rules"
  value = length([
    for key, rule in local.detection_rules : key
    if rule.alert_severity == "critical"
  ])
}