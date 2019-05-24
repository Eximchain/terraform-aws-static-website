# --------------------------------------------------------
# REQUIRED VARIABLES
# --------------------------------------------------------
variable "dns_name" {
    description = "The DNS name the website will be given"
}

variable "domain_root" {
    description = "The root domain hosting this, which must correspond to a public Hosted Zone name"
}

variable "website_bucket_name" {
    description = "Name of the bucket in which to host the static website"
}

variable "log_bucket_name" {
    description = "Name of the bucket to hold logs for the website"
}

variable "github_website_repo" {
    description = "Name of the repo with the static website on it"
}

variable "github_website_branch" {
    description = "Name of the branch with the static website on it"
}

variable "github_token" {
    description = "A token with read permission on the specified repo"
}

# --------------------------------------------------------
# OPTIONAL VARIABLES
# --------------------------------------------------------
variable "aws_region" {
    description = "AWS Region to use"
    default     = "us-east-1"
}

variable "force_destroy_buckets" {
    description = "Set to true to force destroy buckets on terraform destroy"
    default     = false
}

variable "redirect_dns_name" {
    description = "The DNS name to redirect to the website"
    default     = ""
}

variable "redirect_bucket_name" {
    description = "Name of the bucket to host the redirect"
    default     = ""
}

variable "github_owner" {
    description = "Owner the repository with the static website belongs to"
    default     = "Eximchain"
}

variable "acm_cert_domain" {
    description = "The Domain of an ACM certificate that is valid for all domains the site will be hosted at. Will provision one if not provided."
    default     = ""
}