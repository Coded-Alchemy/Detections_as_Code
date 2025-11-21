# ============================================
# Splunk Saved Searches (Detection Rules)
# ============================================
# This resource automatically creates a saved search in Splunk
# for each rule defined in locals.tf
#
# The for_each loop iterates over local.detection_rules
# and creates one splunk_saved_searches resource per rule

