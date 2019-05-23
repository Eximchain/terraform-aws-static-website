# --------------------------------------------------------
# REQUIRED VARIABLES
# --------------------------------------------------------
variable "dns_name" {
    description = "The DNS name the website will be given"
}

variable "domain_root" {
    description = "The root domain hosting this, which must correspond to a public Hosted Zone name"
}

variable "redirect_dns_name" {
    description = "The DNS name to redirect to the website"
}

variable "website_bucket_name" {
    description = "Name of the bucket in which to host the static website"
}

variable "redirect_bucket_name" {
    description = "Name of the bucket to host the redirect"
}

variable "log_bucket_name" {
    description = "Name of the bucket to hold logs for the website"
}

# --------------------------------------------------------
# OPTIONAL VARIABLES
# --------------------------------------------------------
variable "aws_region" {
    description = "AWS Region to use"
    default     = "us-east-1"
}