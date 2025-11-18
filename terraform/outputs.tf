output "deployed_detections" {
  description = "Map of all deployed detection rules"
  value = {
    for key, search in splunk_saved_searches.detections : key => {
      name        = search.name
      id          = search.id
      description = search.description
      severity    = local.detection_rules[key].alert_severity
    }
  }
}

output "detection_count" {
  description = "Total number of detection rules deployed"
  value       = length(keys(splunk_saved_searches.detections))
}

output "high_severity_rules" {
  description = "List of high severity detection rules"
  value = [
    for key, rule in local.detection_rules : rule.name
    if lookup(rule, "alert_severity", "medium") == "high"
  ]
}

output "critical_severity_rules" {
  description = "List of critical severity detection rules"
  value = [
    for key, rule in local.detection_rules : rule.name
    if lookup(rule, "alert_severity", "medium") == "critical"
  ]
}