# terraform-aws-static-website
Module for a simple static website hosted on AWS S3 and Cloudfront

This module requires a GitHub Token set as an environment variable:

```sh
export GITHUB_TOKEN=<A Personal GitHub Token>
```

## Example Vars File

```hcl
// DNS
dns_name          = "eximchain-dev.com"     // REQUIRED: Primary DNS Name
redirect_dns_name = "www.eximchain-dev.com" // OPTIONAL: Only required if you want an alternate DNS name
domain_root       = "eximchain-dev.com"     // REQUIRED: Root domain which we have a Route53 Hosted Zone for

// S3 Bucket Names
website_bucket_name = "eximchain-dev-website"      // REQUIRED: Website Content bucket name
log_bucket_name     = "eximchain-dev-website-logs" // REQUIRED: Log bucket name

// ACM Cert
acm_cert_domain = "eximchain-dev.com" // OPTIONAL: Only required if you want to use a pre-existing ACM cert

acm_cert_arn = "arn:aws:acm:us-east-1:984931625683:certificate/c75c07e9-484c-43f4-a18a-4aa4dee99a91" // OPTIONAL: Allows directly passing certificate ARN

// Website Source
github_website_repo   = "EximchainWebsite"             // REQUIRED: Repository containing the website source
github_website_branch = "master"                       // REQUIRED: Branch of website repo to deploy
deployment_directory  = "build"                        // OPTIONAL: Defaults to deploying repository root
build_command         = "npm install && npm run build" // OPTIONAL: Leave unspecified to deploy pre-built code

force_destroy_buckets = true // OPTIONAL: Set to 'true' to allow the destroy command to empty S3 buckets
```

## Using as Module

```hcl
module "static_website" {
    source = "git@github.com:eximchain/terraform-aws-static-website.git"

    dns_name          = "eximchain-dev.com"
    redirect_dns_name = "www.eximchain-dev.com"
    domain_root       = "eximchain-dev.com"

    website_bucket_name = "eximchain-dev-website"
    log_bucket_name     = "eximchain-dev-website-logs"

    acm_cert_domain = "eximchain-dev.com"

    github_website_repo   = "EximchainWebsite"
    github_website_branch = "master"
    deployment_directory  = "build"
    build_command         = "npm install && npm run build"

    force_destroy_buckets = true
}
```