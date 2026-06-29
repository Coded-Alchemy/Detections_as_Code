# workflow_actions.tf
#
# Manages Splunk workflow actions for the search app via Terraform, using
# the generic splunk_configs_conf resource (same mechanism used for
# macros.conf). The splunk/splunk provider has no dedicated
# "splunk_workflow_actions" resource, so workflow_actions.conf stanzas are
# pushed through this generic conf-file interface instead.
#
# Each resource block below corresponds 1:1 to a [stanza] in
# workflow_actions.conf. The "title" of the resource (e.g. "VT_Lookup_src_ip")
# becomes the stanza name (after the "workflow_actions/" prefix in `name`).
#
# SCHEMA NOTE (confirmed against splunk/terraform-provider-splunk's own
# examples/splunk/basic/main.tf): splunk_configs_conf takes `name` and
# `variables` at the top level, plus an `acl` block. App scoping is set via
# `acl { app = "..." }` -- there is no separate top-level `app` argument.
# This differs from what I originally drafted (which incorrectly duplicated
# `app` at both the top level and inside `acl`); fixed below.

locals {
  workflow_actions_app = "search"
}

# ---------------------------------------------------------------------------
# VirusTotal - IP lookups (one action per field, since a single workflow
# action's link.uri can't conditionally branch on which field was clicked)
# ---------------------------------------------------------------------------

resource "splunk_configs_conf" "vt_lookup_src_ip" {
  name = "workflow_actions/VT_Lookup_src_ip"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "VirusTotal Lookup: $src_ip$"
    fields           = "src_ip"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.virustotal.com/gui/search?query=$src_ip$"
    display_location = "both"
  }
}

resource "splunk_configs_conf" "vt_lookup_dest_ip" {
  name = "workflow_actions/VT_Lookup_dest_ip"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "VirusTotal Lookup: $dest_ip$"
    fields           = "dest_ip"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.virustotal.com/gui/search?query=$dest_ip$"
    display_location = "both"
  }
}

resource "splunk_configs_conf" "vt_lookup_ip" {
  name = "workflow_actions/VT_Lookup_ip"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "VirusTotal Lookup: $ip$"
    fields           = "ip"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.virustotal.com/gui/search?query=$ip$"
    display_location = "both"
  }
}

resource "splunk_configs_conf" "vt_lookup_dest" {
  name = "workflow_actions/VT_Lookup_dest"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "VirusTotal Lookup: $dest$"
    fields           = "dest"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.virustotal.com/gui/search?query=$dest$"
    display_location = "both"
  }
}

# ---------------------------------------------------------------------------
# VirusTotal - hash lookup
# ---------------------------------------------------------------------------

resource "splunk_configs_conf" "vt_lookup_sha256" {
  name = "workflow_actions/VT_Lookup_sha256"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "VirusTotal Lookup: $sha256$"
    fields           = "sha256"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.virustotal.com/gui/search?query=$sha256$"
    display_location = "both"
  }
}

# ---------------------------------------------------------------------------
# AbuseIPDB
# ---------------------------------------------------------------------------

resource "splunk_configs_conf" "abuseipdb_src_ip" {
  name = "workflow_actions/AbuseIPDB_src_ip"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "AbuseIPDB Check: $src_ip$"
    fields           = "src_ip"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.abuseipdb.com/check/$src_ip$"
    display_location = "both"
  }
}

resource "splunk_configs_conf" "abuseipdb_dest_ip" {
  name = "workflow_actions/AbuseIPDB_dest_ip"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "AbuseIPDB Check: $dest_ip$"
    fields           = "dest_ip"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.abuseipdb.com/check/$dest_ip$"
    display_location = "both"
  }
}

# ---------------------------------------------------------------------------
# Shodan
# ---------------------------------------------------------------------------

resource "splunk_configs_conf" "shodan_src_ip" {
  name = "workflow_actions/Shodan_src_ip"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "Shodan Host Lookup: $src_ip$"
    fields           = "src_ip"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.shodan.io/host/$src_ip$"
    display_location = "both"
  }
}

resource "splunk_configs_conf" "shodan_dest_ip" {
  name = "workflow_actions/Shodan_dest_ip"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type             = "link"
    label            = "Shodan Host Lookup: $dest_ip$"
    fields           = "dest_ip"
    "link.method"    = "get"
    "link.target"    = "blank"
    "link.uri"       = "https://www.shodan.io/host/$dest_ip$"
    display_location = "both"
  }
}

# ---------------------------------------------------------------------------
# Internal pivot: all events for a given src_ip / user
# These are "search" type workflow actions, not "link" type.
#
# Attribute names confirmed against the workflow_actions.conf spec/example:
#   search.search_string, search.earliest, search.latest, search.target
# (NOT search.earliest_time / search.latest_time -- that was wrong in my
# first draft and has been corrected here.)
# ---------------------------------------------------------------------------

resource "splunk_configs_conf" "pivot_all_events_src_ip" {
  name = "workflow_actions/Pivot_AllEvents_src_ip"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type                   = "search"
    label                  = "Pivot: All events for $src_ip$ (24h)"
    fields                 = "src_ip"
    "search.search_string" = "index=* src_ip=$src_ip$"
    "search.earliest"      = "-24h@h"
    "search.latest"        = "now"
    "search.app"           = local.workflow_actions_app
    "search.target"        = "blank"
    display_location       = "both"
  }
}

resource "splunk_configs_conf" "pivot_user_activity" {
  name = "workflow_actions/Pivot_UserActivity"
  acl {
    app     = local.workflow_actions_app
    sharing = "app"
  }
  variables = {
    type                   = "search"
    label                  = "Pivot: User activity for $user$ (7d)"
    fields                 = "user"
    "search.search_string" = "index=* user=$user$"
    "search.earliest"      = "-7d@d"
    "search.latest"        = "now"
    "search.app"           = local.workflow_actions_app
    "search.target"        = "blank"
    display_location       = "both"
  }
}
