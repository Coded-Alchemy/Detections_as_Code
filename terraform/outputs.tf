output "saved_search_name" {
  description = "Name of the deployed saved search"
  value       = splunk_saved_searches.windows_defender_disabled.name
}

output "saved_search_id" {
  description = "ID of the deployed saved search"
  value       = splunk_saved_searches.windows_defender_disabled.id
}