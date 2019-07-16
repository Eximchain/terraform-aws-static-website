terraform {
  required_version = ">= 0.12"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  version = "~> 2.2"

  region = var.aws_region
}

provider "local" {
  version = "~> 1.2"
}

provider "template" {
  version = "~> 2.1"
}

data "aws_caller_identity" "current" {
}

# ---------------------------------------------------------------------------------------------------------------------
# LOCALS
# ---------------------------------------------------------------------------------------------------------------------
locals {
  cloudfront_origin_id = "S3-${var.dns_name}"
  create_redirect      = var.redirect_dns_name != ""
  all_aliases          = local.create_redirect ? [var.dns_name, var.redirect_dns_name] : [var.dns_name]
  alternate_aliases    = local.create_redirect ? [var.redirect_dns_name] : []
  provision_acm_cert   = var.acm_cert_domain == "" && var.acm_cert_arn == ""
  hyphenated_dns_name  = replace(var.dns_name, ".", "-")
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
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# WEBSITE CONTENT S3 BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "website_content" {
  bucket = var.website_bucket_name
  acl    = "public-read"

  force_destroy = var.force_destroy_buckets

  website {
    index_document = "index.html"
    error_document = "index.html"
  }

  logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "root/"
  }
}

resource "aws_s3_bucket_policy" "website_content" {
  bucket = aws_s3_bucket.website_content.id
  policy = data.aws_iam_policy_document.public_access_website.json
}

# ---------------------------------------------------------------------------------------------------------------------
# LOG S3 BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
  bucket = var.log_bucket_name
  acl    = "log-delivery-write"

  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_policy" "ses_email_permission" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.ses_email_permission.json
}

# ---------------------------------------------------------------------------------------------------------------------
# SSL CERTIFICATE
# ---------------------------------------------------------------------------------------------------------------------
# For loading existing cert
data "aws_acm_certificate" "ssl_certificate" {
  count = var.acm_cert_domain == "" ? 0 : 1

  domain      = var.acm_cert_domain
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

# For provisioning new cert
resource "aws_acm_certificate" "ssl_certificate" {
  count = local.provision_acm_cert ? 1 : 0

  domain_name               = var.domain_root
  subject_alternative_names = local.alternate_aliases
  validation_method         = "DNS"
}

resource "aws_acm_certificate_validation" "ssl_certificate" {
  count = local.provision_acm_cert ? 1 : 0

  certificate_arn = element(
    coalescelist(aws_acm_certificate.ssl_certificate.*.arn, [""]),
    0,
  )
  validation_record_fqdns = aws_route53_record.cert_validation.*.fqdn

  provisioner "local-exec" {
    command = "sleep 20"
  }
}

resource "aws_route53_record" "cert_validation" {
  count = local.provision_acm_cert ? length(local.all_aliases) : 0

  name    = aws_acm_certificate.ssl_certificate.0.domain_validation_options[count.index]["resource_record_name"]
  type    = aws_acm_certificate.ssl_certificate.0.domain_validation_options[count.index]["resource_record_type"]
  zone_id = data.aws_route53_zone.domain.zone_id
  records = aws_acm_certificate.ssl_certificate.0.domain_validation_options[count.index]["resource_record_value"]
  ttl     = 60
}

# ---------------------------------------------------------------------------------------------------------------------
# CLOUDFRONT DISTRIBUTION
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "website_distribution" {
  enabled = true
  aliases = local.all_aliases

  default_root_object = "index.html"
  is_ipv6_enabled     = true

  comment = "CloudFront distribution for ${var.pretty_project_description}"

  origin {
    domain_name = aws_s3_bucket.website_content.bucket_domain_name
    origin_id   = local.cloudfront_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.website.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.cloudfront_origin_id

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
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    include_cookies = false
  }

  viewer_certificate {
    acm_certificate_arn = element(
      coalescelist(
        compact([var.acm_cert_arn]),
        data.aws_acm_certificate.ssl_certificate.*.arn,
        aws_acm_certificate.ssl_certificate.*.arn,
      ),
      0,
    )
    ssl_support_method = "sni-only"
  }

  depends_on = [aws_acm_certificate_validation.ssl_certificate]
}

resource "aws_cloudfront_origin_access_identity" "website" {
  comment = "Origin Access Identity for ${var.pretty_project_description} Cloudfront Distribution"
}

# ---------------------------------------------------------------------------------------------------------------------
# DNS RECORDS
# ---------------------------------------------------------------------------------------------------------------------
data "aws_route53_zone" "domain" {
  name         = var.domain_root
  private_zone = false
}

resource "aws_route53_record" "website" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = var.dns_name
  type    = "A"

  alias {
    name    = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id = aws_cloudfront_distribution.website_distribution.hosted_zone_id

    evaluate_target_health = false
  }
}

resource "aws_route53_record" "redirect" {
  count = local.create_redirect ? 1 : 0

  zone_id = data.aws_route53_zone.domain.zone_id
  name    = var.redirect_dns_name
  type    = "A"

  alias {
    name    = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id = aws_cloudfront_distribution.website_distribution.hosted_zone_id

    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY PIPLELINE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_codepipeline" "deploy_pipeline" {
  name     = "static-website-${local.hyphenated_dns_name}"
  role_arn = aws_iam_role.website_deploy_codepipeline_iam.arn

  artifact_store {
    location = aws_s3_bucket.deploy_artifacts.id
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner  = var.github_owner
        Repo   = var.github_website_repo
        Branch = var.github_website_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.static_website_builder.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      run_order       = 1
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        BucketName = aws_s3_bucket.website_content.id
        Extract    = "true"
      }
    }

    action {
      name            = "PostDeploy"
      run_order       = 2
      category        = "Invoke"
      owner           = "AWS"
      provider        = "Lambda"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        FunctionName   = aws_lambda_function.post_deploy_lambda.function_name
      }
    }
  }

  depends_on = [aws_iam_role_policy_attachment.codepipeline]
}

resource "aws_s3_bucket" "deploy_artifacts" {
  bucket = "static-website-artifacts-${local.hyphenated_dns_name}"
  acl    = "public-read"

  force_destroy = var.force_destroy_buckets
}

# ---------------------------------------------------------------------------------------------------------------------
# CODEPIPELINE IAM ROLE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "website_deploy_codepipeline_iam" {
  name = "static-website-${var.dns_name}"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codepipeline.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codebuild.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

}

# ---------------------------------------------------------------------------------------------------------------------
# CODEPIPELINE IAM ACCESS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_policy" "codepipeline" {
  name = "static-website-codepipeline-${var.dns_name}"

  policy = data.aws_iam_policy_document.codepipeline.json
}

resource "aws_iam_role_policy_attachment" "codepipeline" {
  role = aws_iam_role.website_deploy_codepipeline_iam.id
  policy_arn = aws_iam_policy.codepipeline.arn
}

data "aws_iam_policy_document" "codepipeline" {
  version = "2012-10-17"

  statement {
    sid = "S3Access"

    effect = "Allow"

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.website_content.arn,
      "${aws_s3_bucket.website_content.arn}/*",
      aws_s3_bucket.deploy_artifacts.arn,
      "${aws_s3_bucket.deploy_artifacts.arn}/*",
    ]
  }

  statement {
    sid = "CloudWatchLogsPolicy"

    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }

  statement {
    sid = "CodeBuildStart"

    effect = "Allow"

    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = ["*"]
  }

  statement {
    sid = "LambdaInvoke"

    effect = "Allow"

    actions = ["lambda:InvokeFunction"]

    // A known issue with the Lambda IAM permissions system makes it impossible
    // to grant more granular permissions.  lambda:InvokeFunction cannot be called
    // on specific functions, and lambda:Invoke is not recognized as a valid policy.
    // Given that only our Lambda can create the CodePipeline which has this role,
    // I think it ought to be fine.  Frustrating, though.  - John
    //
    // https://stackoverflow.com/q/48031334/2128308
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CODEBUILD PROJECT
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_codebuild_project" "static_website_builder" {
  name          = "static-website-${local.hyphenated_dns_name}"
  build_timeout = 10
  service_role  = aws_iam_role.website_deploy_codepipeline_iam.arn

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:2.0"
  }

  artifacts {
    type                = "CODEPIPELINE"
    encryption_disabled = true
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = templatefile("${path.module}/buildspec.yml",
      {
        deployment_directory = var.deployment_directory
        build_command        = var.build_command
        env_file_name        = var.env_file_name
        env                  = var.env
      }
    )
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CODEPIPELINE POST-DEPLOY LAMBDA
# ---------------------------------------------------------------------------------------------------------------------
# Wait ensures that the role is fully created when Lambda tries to assume it.
resource "null_resource" "post_deploy_lambda_wait" {
  provisioner "local-exec" {
    command = "sleep 10"
  }
  
  depends_on = [aws_iam_role.post_deploy_lambda_iam]
}

resource "aws_lambda_function" "post_deploy_lambda" {
  filename         = "${path.module}/static-website-postdeploy-lambda.zip"
  function_name    = "static-website-postdeploy-lambda-${local.hyphenated_dns_name}"
  role             = aws_iam_role.post_deploy_lambda_iam.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/static-website-postdeploy-lambda.zip")
  runtime          = "nodejs8.10"
  timeout          = 10

  environment {
    variables = {
      WEBSITE_CONTENT_BUCKET = aws_s3_bucket.website_content.id
    }
  }

  depends_on = [null_resource.post_deploy_lambda_wait]
}

# ---------------------------------------------------------------------------------------------------------------------
# POSTDEPLOY LAMBDA IAM
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "post_deploy_lambda_iam" {
  name = "static-website-postdeploy-lambda-iam-${local.hyphenated_dns_name}"

  assume_role_policy = data.aws_iam_policy_document.post_deploy_lambda_assume_role.json
}

data "aws_iam_policy_document" "post_deploy_lambda_assume_role" {
  version = "2012-10-17"

  statement {
    sid = "1"

    effect = "Allow"

    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# POSTDEPLOY LAMBDA S3 ACCESS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_policy" "post_deploy_lambda_allow_s3" {
  name = "allow-s3-postdeploy-lambda-${local.hyphenated_dns_name}"

  policy = data.aws_iam_policy_document.post_deploy_lambda_allow_s3.json
}

resource "aws_iam_role_policy_attachment" "post_deploy_lambda_allow_s3" {
  role       = aws_iam_role.post_deploy_lambda_iam.id
  policy_arn = aws_iam_policy.post_deploy_lambda_allow_s3.arn
}

data "aws_iam_policy_document" "post_deploy_lambda_allow_s3" {
  version = "2012-10-17"

  statement {
    sid = "1"

    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:PutBucketWebsite",
      "s3:GetBucketWebsite",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:PutBucketCORS",
      "s3:GetBucketAcl",
      "s3:PutBucketAcl",
      "s3:GetObjectAcl",
      "s3:PutObjectAcl",
      "s3:PutObject",
      "s3:GetObject",
    ]
    resources = [
      aws_s3_bucket.website_content.arn,
      "${aws_s3_bucket.website_content.arn}/*",
    ]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# POSTDEPLOY LAMBDA CLOUDWATCH ACCESS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_policy" "post_deploy_lambda_allow_cloudwatch" {
  name = "allow-cloudwatch-postdeploy-lambda-${local.hyphenated_dns_name}"

  policy = data.aws_iam_policy_document.post_deploy_lambda_allow_cloudwatch.json
}

resource "aws_iam_role_policy_attachment" "post_deploy_lambda_allow_cloudwatch" {
  role       = aws_iam_role.post_deploy_lambda_iam.id
  policy_arn = aws_iam_policy.post_deploy_lambda_allow_cloudwatch.arn
}

data "aws_iam_policy_document" "post_deploy_lambda_allow_cloudwatch" {
  version = "2012-10-17"

  statement {
    sid = "1"

    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# POSTDEPLOY LAMBDA CODEPIPELINE ACCESS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_policy" "post_deploy_lambda_allow_codepipeline" {
  name = "allow-codepipeline-postdeploy-lambda-${local.hyphenated_dns_name}"

  policy = data.aws_iam_policy_document.post_deploy_lambda_allow_codepipeline.json
}

resource "aws_iam_role_policy_attachment" "post_deploy_lambda_allow_codepipeline" {
  role       = aws_iam_role.post_deploy_lambda_iam.id
  policy_arn = aws_iam_policy.post_deploy_lambda_allow_codepipeline.arn
}

data "aws_iam_policy_document" "post_deploy_lambda_allow_codepipeline" {
  version = "2012-10-17"

  statement {
    sid = "1"

    effect = "Allow"

    actions = [
      "codepipeline:PutJobSuccessResult",
      "codepipeline:PutJobFailureResult",
    ]
    resources = ["*"]
  }
}