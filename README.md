# Terraform CloudFront Module

Created by [Wayne Workman](https://github.com/wayneworkman)

[![Blog](https://img.shields.io/badge/Blog-wayne.theworkmans.us-blue)](https://wayne.theworkmans.us/)
[![GitHub](https://img.shields.io/badge/GitHub-wayneworkman-181717?logo=github)](https://github.com/wayneworkman)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Wayne_Workman-0077B5?logo=linkedin)](https://www.linkedin.com/in/wayne-workman-a8b37b353/)
[![SpinnyLights](https://img.shields.io/badge/SpinnyLights-wayneworkman-764ba2)](https://spinnylights.com/wayneworkman)

This Terraform module deploys an AWS Lambda function that uses Amazon Bedrock to detect prompt injection attempts in user input. The module implements the security principles outlined in [this hands-on demo](https://wayne.theworkmans.us/posts/2025/10/2025-10-18-prompt-injection-hands-on-demo.html).


This Terraform module creates a CloudFront distribution with S3 origin, ACM certificate, and optional AWS WAFv2 protection.

## Features

- CloudFront distribution with S3 backend
- Automatic ACM certificate provisioning and validation
- Route53 DNS configuration
- **Optional AWS WAFv2 integration** with:
  - Geo-location blocking
  - IP allowlisting
  - AWS Managed Rules for common web application threats
  - Flexible configuration for different security requirements

## Basic Usage

### Simple CloudFront Distribution (No WAF)

```hcl
module "subdomain-domain-root" {
    source = "git::git@github.com:wayneworkman/terraform_module_cloudfront.git"
    domain_name = "domain.root"
    subdomain_name = "subdomain"
    subject_alternative_names = ["also-known-by-this.other-domain.us"]
    zone_id = "123456"
    project = "subdomain-domain-root"
}
```

### CloudFront with Geo-Blocking WAF

Block traffic from specific countries:

```hcl
module "subdomain-domain-root" {
    source = "git::git@github.com:wayneworkman/terraform_module_cloudfront.git"
    domain_name = "domain.root"
    subdomain_name = "subdomain"
    zone_id = "123456"
    project = "subdomain-domain-root"
    
    # WAF Configuration
    enable_waf = true
    waf_mode = "geo_blocking"
    geo_exclude_countries = ["CN", "RU", "KP"]  # Always blocked
    geo_include_countries = []  # Empty = allow all others
    enable_aws_managed_rules = true
}
```

Allow only specific countries:

```hcl
module "subdomain-domain-root" {
    source = "git::git@github.com:wayneworkman/terraform_module_cloudfront.git"
    domain_name = "domain.root"
    subdomain_name = "subdomain"
    zone_id = "123456"
    project = "subdomain-domain-root"
    
    # WAF Configuration
    enable_waf = true
    waf_mode = "geo_blocking"
    geo_include_countries = ["US", "CA", "GB", "DE"]  # Only allow these
    geo_exclude_countries = ["RU"]  # But never allow Russia, even if in include list
    enable_aws_managed_rules = true
}
```

### CloudFront with IP Allowlist WAF

Only allow traffic from specific IP ranges:

```hcl
module "subdomain-domain-root" {
    source = "git::git@github.com:wayneworkman/terraform_module_cloudfront.git"
    domain_name = "domain.root"
    subdomain_name = "subdomain"
    zone_id = "123456"
    project = "subdomain-domain-root"
    
    # WAF Configuration
    enable_waf = true
    waf_mode = "ip_allowlist"
    allowed_ip_ranges = ["10.0.0.0/8", "192.168.0.0/16", "203.0.113.0/24"]
    allowed_ipv6_ranges = ["2001:db8::/32"]  # Optional IPv6 ranges
    enable_aws_managed_rules = true
}
```

### CloudFront with Combined Protection

Use both geo-blocking and IP allowlisting:

```hcl
module "subdomain-domain-root" {
    source = "git::git@github.com:wayneworkman/terraform_module_cloudfront.git"
    domain_name = "domain.root"
    subdomain_name = "subdomain"
    zone_id = "123456"
    project = "subdomain-domain-root"
    
    # WAF Configuration
    enable_waf = true
    waf_mode = "both"
    allowed_ip_ranges = ["10.0.0.0/8"]  # Allow corporate network
    geo_exclude_countries = ["CN", "RU"]  # Block specific countries
    geo_include_countries = []  # Allow all others (except excluded)
    enable_aws_managed_rules = true
}
```

### CloudFront with Custom Managed Rules

Customize which AWS Managed Rule groups to use:

```hcl
module "subdomain-domain-root" {
    source = "git::git@github.com:wayneworkman/terraform_module_cloudfront.git"
    domain_name = "domain.root"
    subdomain_name = "subdomain"
    zone_id = "123456"
    project = "subdomain-domain-root"
    
    # WAF Configuration
    enable_waf = true
    waf_mode = "geo_blocking"
    geo_exclude_countries = ["CN", "RU"]  # Block these countries
    geo_include_countries = []  # Empty = allow all others
    enable_aws_managed_rules = true
    
    # Custom managed rule configuration
    managed_rule_groups = [
        {
            name = "AWSManagedRulesCommonRuleSet"
            priority = 10
            override_action = "none"  # Apply all rules
        },
        {
            name = "AWSManagedRulesAmazonIpReputationList"
            priority = 20
            override_action = "none"
        },
        {
            name = "AWSManagedRulesKnownBadInputsRuleSet"
            priority = 30
            override_action = "count"  # Monitor only, don't block
        },
        {
            name = "AWSManagedRulesSQLiRuleSet"
            priority = 40
            override_action = "none"
        }
    ]
}
```

## Variables

### Core Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `domain_name` | string | - | The root domain name (required) |
| `subdomain_name` | string | `""` | The subdomain to prepend to the domain name |
| `subject_alternative_names` | list(string) | `[]` | Additional domain names for the certificate |
| `zone_id` | string | - | Route53 hosted zone ID (required) |
| `project` | string | - | Project name for tagging (required) |
| `index_document` | string | `"index.html"` | Default index document |
| `error_document` | string | `"error.html"` | Default error document |

### WAF Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_waf` | bool | `false` | Enable AWS WAFv2 protection for CloudFront |
| `waf_mode` | string | `"geo_blocking"` | WAF mode: 'geo_blocking', 'ip_allowlist', or 'both' |
| `waf_default_action` | string | `"allow"` | Default action for requests not matching any rule: 'allow' or 'block' |

#### Geo-Blocking Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `geo_include_countries` | list(string) | `[]` | ISO 3166 alpha-2 country codes to allow. Empty list = allow all countries (except excluded) |
| `geo_exclude_countries` | list(string) | `[]` | ISO 3166 alpha-2 country codes to block. Takes precedence over include list |

#### IP Allowlist Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `allowed_ip_ranges` | list(string) | `[]` | IPv4 CIDR ranges to allow (e.g., ['10.0.0.0/8', '192.168.1.0/24']) |
| `allowed_ipv6_ranges` | list(string) | `[]` | IPv6 CIDR ranges to allow |

#### AWS Managed Rules Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_aws_managed_rules` | bool | `true` | Enable AWS Managed Rule groups for common protections |
| `managed_rule_groups` | list(object) | See below | AWS Managed Rule groups to enable |

Default managed rule groups:
```hcl
[
    {
        name = "AWSManagedRulesCommonRuleSet"
        priority = 10
        override_action = "none"
    },
    {
        name = "AWSManagedRulesAmazonIpReputationList"
        priority = 20
        override_action = "none"
    }
]
```

## AWS Managed Rule Groups

### Recommended Rule Groups

1. **AWSManagedRulesCommonRuleSet** (100 WCU)
   - Provides protection against OWASP Top 10 vulnerabilities
   - Includes rules for SQL injection, XSS, size restrictions
   - Recommended for all deployments

2. **AWSManagedRulesAmazonIpReputationList** (25 WCU)
   - Blocks requests from known malicious IP addresses
   - Automatically updated by AWS

3. **AWSManagedRulesKnownBadInputsRuleSet** (200 WCU)
   - Blocks request patterns known to be invalid or malicious
   - Good for additional protection against exploits

4. **AWSManagedRulesSQLiRuleSet** (200 WCU)
   - Specific protection against SQL injection attacks
   - Recommended for applications with database backends

5. **AWSManagedRulesLinuxRuleSet** (200 WCU)
   - Protection specific to Linux-based applications
   - Blocks exploits targeting Linux vulnerabilities

## Important Notes

### WAFv2 Requirements

1. **Region Requirement**: WAFv2 resources for CloudFront MUST be created in the `us-east-1` region. The module handles this automatically using a provider alias.

2. **Scope**: All WAFv2 resources use the `CLOUDFRONT` scope, which is required for CloudFront distributions.

3. **CloudFront Geo Restriction**: If using WAF geo-blocking, do NOT also use CloudFront's built-in geo restriction feature. CloudFront geo restriction prevents blocked requests from reaching WAF.

### Geo-Blocking Logic

The geo-blocking feature uses include and exclude lists with the following precedence rules:

1. **Exclude list always wins**: If a country is in `geo_exclude_countries`, it's blocked regardless of include list
2. **Empty include list = allow all**: When `geo_include_countries` is empty, all countries are allowed (except those explicitly excluded)
3. **Non-empty include list = allow only those**: When `geo_include_countries` has values, ONLY those countries are allowed (minus any excluded)

#### Examples:

**Block specific countries only:**
```hcl
geo_include_countries = []          # Allow all countries
geo_exclude_countries = ["CN", "RU"] # Except China and Russia
```

**Allow specific countries only:**
```hcl
geo_include_countries = ["US", "CA", "GB"] # Only allow US, Canada, UK
geo_exclude_countries = []                 # No additional exclusions
```

**Allow specific countries with exceptions:**
```hcl
geo_include_countries = ["US", "CA", "MX", "GB", "FR", "DE"] # North America + Europe
geo_exclude_countries = ["FR"]  # But block France even though it's in include list
# Result: Only US, CA, MX, GB, DE are allowed
```

### CIDR Notation

When specifying IP ranges:
- Single IPv4 address: `192.0.2.44/32`
- IPv4 range: `192.0.2.0/24` (covers 192.0.2.0 to 192.0.2.255)
- Single IPv6 address: `2001:db8::1/128`
- IPv6 range: `2001:db8::/32`

### Country Codes

Use ISO 3166 alpha-2 country codes for geo-blocking:
- United States: `US`
- China: `CN`
- Russia: `RU`
- United Kingdom: `GB`
- Germany: `DE`
- Full list: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2

### Cost Considerations

WAFv2 pricing includes:
- Web ACL: $5.00/month
- Rule evaluations: $1.00 per million requests
- Managed rule groups: $1.00/month per rule group
- Request sampling: Additional charges may apply

## Outputs

The module provides the following outputs:
- CloudFront distribution ID and domain name
- S3 bucket name and ARN
- ACM certificate ARN
- WAF Web ACL ARN (if enabled)
- WAF Web ACL ID (if enabled)

## Destroying Resources

To destroy the resources created by this module:

```hcl
module "subdomain-domain-root" {
    source = "git::git@github.com:wayneworkman/tfmod_cloudfront.git//provider_only"
}
```

## Security Best Practices

1. **Start with monitoring**: Use `override_action = "count"` on managed rules initially to understand traffic patterns before blocking.

2. **Layer your defenses**: Combine geo-blocking with IP allowlisting for sensitive applications.

3. **Regular reviews**: Periodically review CloudWatch metrics and WAF sampled requests to tune your rules.

4. **Use managed rules**: AWS Managed Rules are regularly updated to address new threats.

5. **Least privilege**: For internal applications, prefer IP allowlisting over geo-blocking.

## Troubleshooting

### Common Issues

1. **WAF not blocking traffic**: Ensure `waf_mode` matches your configuration and rules have correct priorities.

2. **Legitimate traffic blocked**: Check CloudWatch metrics and sampled requests. Consider using `count` mode first.

3. **Certificate validation fails**: Ensure the Route53 zone ID is correct and you have permission to create DNS records.

4. **WAF association fails**: Verify WAFv2 resources are in us-east-1 region with CLOUDFRONT scope.

## License

[Specify your license here]

## Support

[Specify support contact or repository issues URL]