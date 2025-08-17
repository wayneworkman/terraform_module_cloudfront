

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}


resource "aws_acm_certificate" "cert" {
  domain_name               = local.full_domain
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"
  provider                  = aws.virginia
}


resource "aws_route53_record" "cert" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  depends_on              = [aws_route53_record.cert]
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert : record.fqdn]
  provider                = aws.virginia
}



resource "aws_s3_bucket" "bucket" {
  bucket = local.full_domain
  tags = {
    Name    = local.full_domain
    Project = var.project
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


resource "aws_s3_bucket_website_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  index_document {
    suffix = var.index_document
  }
  error_document {
    key = var.error_document
  }
}


resource "aws_s3_bucket_policy" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  policy = <<POLICY
{
    "Version":"2012-10-17",
    "Id":"PolicyForCloudFrontPrivateContent",
    "Statement":[
        {
            "Sid":"1",
            "Effect":"Allow",
            "Principal":{
                "AWS":"${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"
            },
            "Action":"s3:GetObject",
            "Resource":"arn:aws:s3:::${local.full_domain}/*"
        }
    ]
}
POLICY
}


resource "aws_route53_record" "site_record" {
  zone_id = var.zone_id
  name    = local.full_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}


locals {
  s3_origin_id = "myS3Origin"
  full_domain  = var.subdomain_name != "" ? format("%s.%s", var.subdomain_name, var.domain_name) : var.domain_name
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Some comment"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [aws_acm_certificate_validation.cert]
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = var.index_document


  aliases = concat(var.subject_alternative_names, [local.full_domain])

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 600
    max_ttl                = 900
  }

  price_class = "PriceClass_100"

  tags = {
    Name    = local.full_domain
    Project = var.project
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  web_acl_id = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}


