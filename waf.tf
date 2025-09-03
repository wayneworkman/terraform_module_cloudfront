locals {
  waf_name_prefix = replace(replace(local.full_domain, ".", "_"), "-", "_")
}

resource "aws_wafv2_ip_set" "ipv4_allowlist" {
  count              = var.enable_waf && (var.waf_mode == "ip_allowlist" || var.waf_mode == "both") && length(var.allowed_ip_ranges) > 0 ? 1 : 0
  provider           = aws.virginia
  name               = "${local.waf_name_prefix}_ipv4_allowlist"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ip_ranges

  tags = {
    Name    = "${local.full_domain}-ipv4-allowlist"
    Project = var.project
  }
}

resource "aws_wafv2_ip_set" "ipv6_allowlist" {
  count              = var.enable_waf && (var.waf_mode == "ip_allowlist" || var.waf_mode == "both") && length(var.allowed_ipv6_ranges) > 0 ? 1 : 0
  provider           = aws.virginia
  name               = "${local.waf_name_prefix}_ipv6_allowlist"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV6"
  addresses          = var.allowed_ipv6_ranges

  tags = {
    Name    = "${local.full_domain}-ipv6-allowlist"
    Project = var.project
  }
}

resource "aws_wafv2_web_acl" "main" {
  count    = var.enable_waf ? 1 : 0
  provider = aws.virginia
  name     = "${local.waf_name_prefix}_waf"
  scope    = "CLOUDFRONT"

  default_action {
    dynamic "allow" {
      for_each = var.waf_default_action == "allow" ? [1] : []
      content {}
    }
    dynamic "block" {
      for_each = var.waf_default_action == "block" ? [1] : []
      content {}
    }
  }

  dynamic "rule" {
    for_each = var.enable_rate_limiting ? [1] : []
    content {
      name     = "RateLimitPerIP"
      priority = 0

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit                 = var.rate_limit_requests
          aggregate_key_type    = "IP"
          evaluation_window_sec = var.rate_limit_evaluation_window_sec
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_name_prefix}_rate_limit"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.waf_mode == "geo_blocking" || var.waf_mode == "both" ? (length(var.geo_exclude_countries) > 0 ? [1] : []) : []
    content {
      name     = "BlockExcludedCountries"
      priority = 1

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.geo_exclude_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_name_prefix}_blocked_countries"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.waf_mode == "ip_allowlist" || var.waf_mode == "both" ? (length(var.allowed_ip_ranges) > 0 ? [1] : []) : []
    content {
      name     = "AllowIPv4List"
      priority = 2

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.ipv4_allowlist[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_name_prefix}_allowed_ipv4"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.waf_mode == "ip_allowlist" || var.waf_mode == "both" ? (length(var.allowed_ipv6_ranges) > 0 ? [1] : []) : []
    content {
      name     = "AllowIPv6List"
      priority = 3

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.ipv6_allowlist[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_name_prefix}_allowed_ipv6"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.waf_mode == "ip_allowlist" || var.waf_mode == "both" ? [1] : []
    content {
      name     = "BlockNonAllowlistedIPs"
      priority = 4

      action {
        block {}
      }

      statement {
        not_statement {
          statement {
            # Use OR statement only when we have multiple IP sets, otherwise use single statement
            dynamic "or_statement" {
              for_each = (length(var.allowed_ip_ranges) > 0 && length(var.allowed_ipv6_ranges) > 0) ? [1] : []
              content {
                dynamic "statement" {
                  for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
                  content {
                    ip_set_reference_statement {
                      arn = aws_wafv2_ip_set.ipv4_allowlist[0].arn
                    }
                  }
                }
                dynamic "statement" {
                  for_each = length(var.allowed_ipv6_ranges) > 0 ? [1] : []
                  content {
                    ip_set_reference_statement {
                      arn = aws_wafv2_ip_set.ipv6_allowlist[0].arn
                    }
                  }
                }
              }
            }
            # Use single IPv4 statement when only IPv4 is configured
            dynamic "ip_set_reference_statement" {
              for_each = (length(var.allowed_ip_ranges) > 0 && length(var.allowed_ipv6_ranges) == 0) ? [1] : []
              content {
                arn = aws_wafv2_ip_set.ipv4_allowlist[0].arn
              }
            }
            # Use single IPv6 statement when only IPv6 is configured
            dynamic "ip_set_reference_statement" {
              for_each = (length(var.allowed_ip_ranges) == 0 && length(var.allowed_ipv6_ranges) > 0) ? [1] : []
              content {
                arn = aws_wafv2_ip_set.ipv6_allowlist[0].arn
              }
            }
            # Use dummy statement when no IPs are configured
            dynamic "byte_match_statement" {
              for_each = (length(var.allowed_ip_ranges) == 0 && length(var.allowed_ipv6_ranges) == 0) ? [1] : []
              content {
                search_string = "block-all-when-no-ips-configured"
                field_to_match {
                  single_header {
                    name = "x-never-exists-header"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
                positional_constraint = "CONTAINS"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_name_prefix}_blocked_non_allowlisted"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.waf_mode == "geo_blocking" || var.waf_mode == "both" ? (length(var.geo_include_countries) > 0 ? [1] : []) : []
    content {
      name     = "AllowIncludedCountries"
      priority = 5

      action {
        allow {}
      }

      statement {
        geo_match_statement {
          country_codes = var.geo_include_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_name_prefix}_allowed_countries"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.waf_mode == "geo_blocking" || var.waf_mode == "both" ? (length(var.geo_include_countries) > 0 ? [1] : []) : []
    content {
      name     = "BlockNonIncludedCountries"
      priority = 6

      action {
        block {}
      }

      statement {
        not_statement {
          statement {
            geo_match_statement {
              country_codes = var.geo_include_countries
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_name_prefix}_blocked_non_included"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.enable_aws_managed_rules ? var.managed_rule_groups : []
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = rule.value.override_action == "none" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.override_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_name_prefix}_${lower(replace(rule.value.name, "AWSManagedRules", ""))}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.waf_name_prefix}_waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name    = "${local.full_domain}-waf"
    Project = var.project
  }
}

