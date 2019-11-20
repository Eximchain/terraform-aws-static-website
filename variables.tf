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

variable "acm_cert_arn" {
  description = "The ARN of an ACM certificate that is valid for all domains the site will be hosted at. Will provision one if not provided."
  default     = ""
}

variable "pretty_project_description" {
  description = "A pretty, human-readable name for the project to be used in comments"
  default     = "static website"
}

variable "deployment_directory" {
  description = "The directory in the repository in which the artifacts to deploy can be found"
  default     = "./"
}

variable "build_command" {
  description = "The command to use to build the Website, if you want the pipeline to build it (e.g. 'npm run build').  If not specified, the pipeline will assume the static bundle is already built."
  default     = ":"
}

variable "npm_user" {
  description = "Username for the NPM account which the builder should log into before installing dependencies."
  // Using an empty string causes an error on apply
  default     = "NULL"
}

variable "npm_pass" {
  description = "Password for the NPM account which the builder should log into before installing dependencies."
  // Using an empty string causes an error on apply
  default     = "NULL"
}

variable "npm_email" {
  description = "Email for the NPM account which the builder should log into before installing dependencies."
  // Using an empty string causes an error on apply
  default     = "NULL"
}

variable "env" {
  description = "Environment variables to be included in a .env file"
  default     = {}
  type        = map(string)
}

variable "env_file_name" {
  description = "Name of the file that will contain the .env variables"
  default     = ".env"
}