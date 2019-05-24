output "cloudfront_domain_name" {
    value = "${aws_cloudfront_distribution.website_distribution.domain_name}"
}

output "cloudfront_distribution_id" {
    value = "${aws_cloudfront_distribution.website_distribution.id}"
}

output "cloudfront_domain_hosted_zone_id" {
    value = "${aws_cloudfront_distribution.website_distribution.hosted_zone_id}"
}

output "website_dns" {
    value = "${aws_route53_record.website.fqdn}"
}

output "redirect_dns" {
    value = "${element(coalescelist(aws_route53_record.redirect.*.fqdn, list("")), 0)}"
}