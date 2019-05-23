# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
    version = "~> 1.57"

    region  = "${var.aws_region}"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------------------------------------------------
# LOCALS
# ---------------------------------------------------------------------------------------------------------------------
locals {
    cloudfront_origin_id = "S3-${var.dns_name}"
    create_redirect      = "${var.redirect_bucket_name != "" && var.redirect_dns_name != ""}"
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 BUCKET POLICIES
# ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "public_access_website" {
    statement {
        sid       = "PublicReadGetObject"
        effect    = "Allow"
        actions   = ["s3:GetObject"]
        resources = ["${aws_s3_bucket.website_content.arn}/*"]

        principals {
            type        = "*"
            identifiers = ["*"]
        }
    }
}

data "aws_iam_policy_document" "public_access_redirect" {
    count = "${local.create_redirect ? 1 : 0}"

    statement {
        sid       = "PublicReadGetObject"
        effect    = "Allow"
        actions   = ["s3:GetObject"]
        resources = ["${aws_s3_bucket.redirect.arn}/*"]

        principals {
            type        = "*"
            identifiers = ["*"]
        }
    }
}

data "aws_iam_policy_document" "ses_email_permission" {
    statement {
        sid       = "GiveSESPermissionToWriteEmail"
        effect    = "Allow"
        actions   = ["s3:PutObject"]
        resources = ["${aws_s3_bucket.logs.arn}/*"]

        principals {
            type        = "Service"
            identifiers = ["ses.amazonaws.com"]
        }

        condition {
            test     = "StringEquals"
            variable = "aws:Referer"
            values   = ["${data.aws_caller_identity.current.account_id}"]
        }
    }
}

# ---------------------------------------------------------------------------------------------------------------------
# WEBSITE CONTENT S3 BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "website_content" {
    bucket = "${var.website_bucket_name}"
    acl    = "public-read"

    force_destroy = "${var.force_destroy_buckets}"

    website {
        index_document = "index.html"
        error_document = "index.html"
    }

    logging {
        target_bucket = "${aws_s3_bucket.logs.bucket}"
        target_prefix = "root/"
    }
}

resource "aws_s3_bucket_policy" "website_content" {
    bucket = "${aws_s3_bucket.website_content.bucket}"
    policy = "${data.aws_iam_policy_document.public_access_website.json}"
}

# ---------------------------------------------------------------------------------------------------------------------
# REDIRECT S3 BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "redirect" {
    count = "${local.create_redirect ? 1 : 0}"

    bucket = "${var.redirect_bucket_name}"
    acl    = "public-read"

    force_destroy = "${var.force_destroy_buckets}"

    website {
        redirect_all_requests_to = "http://${aws_s3_bucket.website_content.bucket}"
    }
}

resource "aws_s3_bucket_policy" "redirect" {
    count = "${local.create_redirect ? 1 : 0}"

    bucket = "${aws_s3_bucket.redirect.bucket}"
    policy = "${data.aws_iam_policy_document.public_access_redirect.json}"
}

# ---------------------------------------------------------------------------------------------------------------------
# LOG S3 BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
    bucket = "${var.log_bucket_name}"
    acl    = "log-delivery-write"

    force_destroy = "${var.force_destroy_buckets}"
}

resource "aws_s3_bucket_policy" "ses_email_permission" {
    bucket = "${aws_s3_bucket.logs.bucket}"
    policy = "${data.aws_iam_policy_document.ses_email_permission.json}"
}

# ---------------------------------------------------------------------------------------------------------------------
# SSL CERTIFICATE
# ---------------------------------------------------------------------------------------------------------------------
data "aws_acm_certificate" "ssl_certificate" {
    # Currently hand-managed
    domain      = "${var.dns_name}"
    types       = ["AMAZON_ISSUED"]
    most_recent = true
}

# ---------------------------------------------------------------------------------------------------------------------
# CLOUDFRONT DISTRIBUTION
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "website_distribution" {
    enabled = true
    aliases = "${split(",", local.create_redirect ? join(",", list(var.dns_name, var.redirect_dns_name)) : var.dns_name)}"

    default_root_object = "index.html"
    is_ipv6_enabled     = true

    comment = "CloudFront distribution for static website"

    origin {
        domain_name = "${aws_s3_bucket.website_content.bucket_domain_name}"
        origin_id   = "${local.cloudfront_origin_id}"

        s3_origin_config {
            origin_access_identity = "${aws_cloudfront_origin_access_identity.website.cloudfront_access_identity_path}"
        }
    }

    default_cache_behavior {
        allowed_methods  = ["GET", "HEAD"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = "${local.cloudfront_origin_id}"

        forwarded_values {
            query_string = true
            headers      = ["Origin"]

            cookies {
                forward = "all"
            }
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl                = 0
        default_ttl            = 86400
        max_ttl                = 31536000

        smooth_streaming = false
        compress         = false
    }

    custom_error_response {
        error_code         = 404
        response_code      = 200
        response_page_path = "/index.html"

        error_caching_min_ttl = 0
    }

    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }

    logging_config {
        bucket          = "${aws_s3_bucket.logs.bucket_domain_name}"
        include_cookies = false
    }

    viewer_certificate {
        acm_certificate_arn = "${data.aws_acm_certificate.ssl_certificate.arn}"
        ssl_support_method  = "sni-only"
    }
}

resource "aws_cloudfront_origin_access_identity" "website" {
    comment = "Origin Access Identity for static website Cloudfront Distribution"
}

# ---------------------------------------------------------------------------------------------------------------------
# DNS RECORDS
# ---------------------------------------------------------------------------------------------------------------------
data "aws_route53_zone" "domain" {
  name         = "${var.domain_root}"
  private_zone = false
}

resource "aws_route53_record" "website" {
    zone_id = "${data.aws_route53_zone.domain.zone_id}"
    name    = "${var.dns_name}"
    type    = "A"

    alias {
        name    = "${aws_cloudfront_distribution.website_distribution.domain_name}"
        zone_id = "${aws_cloudfront_distribution.website_distribution.hosted_zone_id}"

        evaluate_target_health = false
    }
}

resource "aws_route53_record" "redirect" {
    count = "${local.create_redirect ? 1 : 0}"

    zone_id = "${data.aws_route53_zone.domain.zone_id}"
    name    = "${var.redirect_dns_name}"
    type    = "A"

    alias {
        name    = "${aws_cloudfront_distribution.website_distribution.domain_name}"
        zone_id = "${aws_cloudfront_distribution.website_distribution.hosted_zone_id}"

        evaluate_target_health = false
    }
}

# ---------------------------------------------------------------------------------------------------------------------
# WEBSITE CONTENT
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket_object" "index" {
  bucket = "${aws_s3_bucket.website_content.id}"
  key    = "index.html"
  source = "${path.module}/loading.html"

  content_type = "text/html"
}