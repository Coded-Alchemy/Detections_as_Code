# macros.tf

resource "splunk_configs_conf" "macro_port_to_service" {
  name = "macros/port_to_service(1)"

  variables = {
    args        = "port"
    definition  = <<-EOT
      case(
        $port$=20,   "FTP Data",
        $port$=21,   "FTP Control",
        $port$=22,   "SSH",
        $port$=23,   "Telnet",
        $port$=25,   "SMTP",
        $port$=53,   "DNS",
        $port$=67,   "DHCP Server",
        $port$=68,   "DHCP Client",
        $port$=80,   "HTTP",
        $port$=110,  "POP3",
        $port$=135,  "RPC",
        $port$=137,  "NetBIOS Name",
        $port$=138,  "NetBIOS Datagram",
        $port$=139,  "NetBIOS Session",
        $port$=143,  "IMAP",
        $port$=389,  "LDAP",
        $port$=443,  "HTTPS",
        $port$=445,  "SMB",
        $port$=465,  "SMTPS",
        $port$=514,  "Syslog",
        $port$=587,  "SMTP Submission",
        $port$=636,  "LDAPS",
        $port$=993,  "IMAPS",
        $port$=995,  "POP3S",
        $port$=1433, "MSSQL",
        $port$=1723, "PPTP",
        $port$=3306, "MySQL",
        $port$=3389, "RDP",
        $port$=4444, "Metasploit Default",
        $port$=4899, "Radmin",
        $port$=5900, "VNC",
        $port$=6667, "IRC",
        $port$=8080, "HTTP Proxy",
        $port$=8443, "HTTPS Alt",
        $port$=9200, "Elasticsearch",
        $port$=27017,"MongoDB",
        true,        "Unknown"
      )
    EOT
    iseval      = "1"
    description = "Returns the service name for a given port number. Usage: eval service=`port_to_service(dest_port)`"
  }

  acl {
    app   = "malware_lab"
    owner = "nobody"
    read  = ["*"]
    write = ["admin", "power"]
  }
}