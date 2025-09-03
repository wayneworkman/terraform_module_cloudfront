variable "domain_name" {
  type = string
}

variable "subdomain_name" {
  type        = string
  default     = ""
  description = "The subdomain to prepend to the domain name (e.g., 'www', 'test'). Do not include a trailing dot."
}

variable "subject_alternative_names" {
  type    = list(string)
  default = []
}

variable "zone_id" {
  type = string
}

variable "index_document" {
  type    = string
  default = "index.html"
}

variable "error_document" {
  type    = string
  default = "error.html"
}

variable "project" {
  type = string
}

variable "enable_waf" {
  type        = bool
  default     = false
  description = "Enable AWS WAFv2 protection for CloudFront"
}

variable "waf_mode" {
  type        = string
  default     = "geo_blocking"
  description = "WAF mode: 'geo_blocking', 'ip_allowlist', or 'both'"
  validation {
    condition     = contains(["geo_blocking", "ip_allowlist", "both"], var.waf_mode)
    error_message = "Must be 'geo_blocking', 'ip_allowlist', or 'both'"
  }
}

variable "waf_default_action" {
  type        = string
  default     = "allow"
  description = "Default action for requests not matching any rule: 'allow' or 'block'"
  validation {
    condition     = contains(["allow", "block"], var.waf_default_action)
    error_message = "Must be 'allow' or 'block'"
  }
}

variable "geo_include_countries" {
  type        = list(string)
  default     = []
  description = "ISO 3166 alpha-2 country codes to allow. Empty list = allow all countries (except excluded)"
}

variable "geo_exclude_countries" {
  type        = list(string)
  default     = []
  description = "ISO 3166 alpha-2 country codes to block. Takes precedence over include list"
}

variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDR ranges to allow (e.g., ['10.0.0.0/8', '192.168.1.0/24'])"
}

variable "allowed_ipv6_ranges" {
  type        = list(string)
  default     = []
  description = "IPv6 CIDR ranges to allow"
}

variable "enable_aws_managed_rules" {
  type        = bool
  default     = true
  description = "Enable AWS Managed Rule groups for common protections"
}

variable "managed_rule_groups" {
  type = list(object({
    name            = string
    priority        = number
    override_action = string
  }))
  default = [
    {
      name            = "AWSManagedRulesCommonRuleSet"
      priority        = 10
      override_action = "none"
    },
    {
      name            = "AWSManagedRulesAmazonIpReputationList"
      priority        = 20
      override_action = "none"
    }
  ]
  description = "AWS Managed Rule groups to enable"
}

variable "enable_rate_limiting" {
  type        = bool
  default     = false
  description = "Enable rate limiting per IP address"
}

variable "rate_limit_requests" {
  type        = number
  default     = 2000
  description = "Number of requests allowed per IP address within the evaluation window"
}

variable "rate_limit_evaluation_window_sec" {
  type        = number
  default     = 300
  description = "Evaluation window in seconds for rate limiting (300 = 5 minutes, 60 = 1 minute)"
}