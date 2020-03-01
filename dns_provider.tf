#------------------------------------------------------------------------------#
# Locals
#------------------------------------------------------------------------------#

locals {
  endpoints_dns_provider_gen_cert = [
    for endpoint in local.endpoints_dns_provider :
    endpoint
    if endpoint.gen_cert == true
  ]

  endpoints_dns_provider_pre_cert = [
    for endpoint in local.endpoints_dns_provider :
    endpoint
    if endpoint.gen_cert == false
  ]
}

#------------------------------------------------------------------------------#
# Provider DNS
#------------------------------------------------------------------------------#

data "aws_route53_zone" "dns_provider" {
  count = length(local.endpoints_dns_provider)

  name = local.endpoints_dns_provider[count.index].zone_name

  provider = aws.dns
}

resource "aws_route53_record" "dns_provider_ipv4" {
  count = length(local.endpoints_dns_provider)

  zone_id = data.aws_route53_zone.dns_provider[count.index].id
  name    = local.endpoints_dns_provider[count.index].subdomain == null ? "" : local.endpoints_dns_provider[count.index].subdomain
  type    = "A"

  alias {
    name    = aws_lb.main.dns_name
    zone_id = aws_lb.main.zone_id

    evaluate_target_health = true
  }

  allow_overwrite = true

  provider = aws.dns
}

resource "aws_route53_record" "dns_provider_ipv6" {
  count = var.config.ip_address_type == "dualstack" ? length(local.endpoints_dns_provider) : 0

  zone_id = data.aws_route53_zone.dns_provider[count.index].id
  name    = local.endpoints_dns_provider[count.index].subdomain == null ? "" : local.endpoints_dns_provider[count.index].subdomain
  type    = "AAAA"

  alias {
    name    = aws_lb.main.dns_name
    zone_id = aws_lb.main.zone_id

    evaluate_target_health = true
  }

  allow_overwrite = true

  provider = aws.dns
}

#------------------------------------------------------------------------------#
# Provider Certificates
#------------------------------------------------------------------------------#

data "aws_route53_zone" "dns_provider_gen_cert" {
  count = length(local.endpoints_dns_provider_gen_cert)

  name = local.endpoints_dns_provider_gen_cert[count.index].zone_name

  provider = aws.dns
}

resource "aws_acm_certificate" "dns_provider" {
  count = length(local.endpoints_dns_provider_gen_cert)

  domain_name       = local.endpoints_dns_provider_gen_cert[count.index].subdomain == null ? data.aws_route53_zone.dns_provider[count.index].name : format("%s.%s", local.endpoints_dns_provider_gen_cert[count.index].subdomain, data.aws_route53_zone.dns_provider[count.index].name)
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  domain_validation_options_dns_provider = flatten(aws_acm_certificate.dns_provider.*.domain_validation_options)
}

resource "aws_route53_record" "certificate_validation_dns_provider" {
  count = length(local.endpoints_dns_provider_gen_cert)

  zone_id = data.aws_route53_zone.dns_provider[count.index].id
  name    = local.domain_validation_options_dns_provider[count.index]["resource_record_name"]
  type    = local.domain_validation_options_dns_provider[count.index]["resource_record_type"]
  records = [local.domain_validation_options_dns_provider[count.index]["resource_record_value"]]
  ttl     = 60

  allow_overwrite = true

  provider = aws.dns
}

locals {
  validation_record_fqdns_dns_provider = flatten(aws_route53_record.certificate_validation_dns_provider.*.fqdn)
}

resource "aws_acm_certificate_validation" "dns_provider" {
  count = length(local.endpoints_dns_provider_gen_cert)

  certificate_arn         = aws_acm_certificate.dns_provider[count.index].arn
  validation_record_fqdns = [local.validation_record_fqdns_dns_provider[count.index]]
}

