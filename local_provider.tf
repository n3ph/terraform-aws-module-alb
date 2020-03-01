#------------------------------------------------------------------------------#
# Locals
#------------------------------------------------------------------------------#

locals {
  endpoints_local_provider_gen_cert = [
    for endpoint in local.endpoints_local_provider :
    endpoint
    if endpoint.gen_cert == true
  ]

  endpoints_local_provider_pre_cert = [
    for endpoint in local.endpoints_local_provider :
    endpoint
    if endpoint.gen_cert == false
  ]
}

#------------------------------------------------------------------------------#
# Local DNS
#------------------------------------------------------------------------------#

data "aws_route53_zone" "local_provider" {
  count = length(local.endpoints_local_provider)

  name = local.endpoints_local_provider[count.index].zone_name
}

resource "aws_route53_record" "local_provider_ipv4" {
  count = length(local.endpoints_local_provider)

  zone_id = data.aws_route53_zone.local_provider[count.index].id
  name    = local.endpoints_local_provider[count.index].subdomain == null ? "" : local.endpoints_local_provider[count.index].subdomain
  type    = "A"

  alias {
    name    = aws_lb.main.dns_name
    zone_id = aws_lb.main.zone_id

    evaluate_target_health = true
  }

  allow_overwrite = true
}

resource "aws_route53_record" "local_provider_ipv6" {
  count = var.config.ip_address_type == "dualstack" ? length(local.endpoints_local_provider) : 0

  zone_id = data.aws_route53_zone.local_provider[count.index].id
  name    = local.endpoints_local_provider[count.index].subdomain == null ? "" : local.endpoints_local_provider[count.index].subdomain
  type    = "AAAA"

  alias {
    name    = aws_lb.main.dns_name
    zone_id = aws_lb.main.zone_id

    evaluate_target_health = true
  }

  allow_overwrite = true
}

#------------------------------------------------------------------------------#
# Local Certificates
#------------------------------------------------------------------------------#

data "aws_route53_zone" "local_provider_gen_cert" {
  count = length(local.endpoints_local_provider_gen_cert)

  name = local.endpoints_local_provider_gen_cert[count.index].zone_name
}

resource "aws_acm_certificate" "local_provider" {
  count = length(local.endpoints_local_provider_gen_cert)

  domain_name       = local.endpoints_local_provider_gen_cert[count.index].subdomain == null ? data.aws_route53_zone.local_provider[count.index].name : format("%s.%s", local.endpoints_local_provider_gen_cert[count.index].subdomain, data.aws_route53_zone.local_provider[count.index].name)
  validation_method = "DNS"
}

locals {
  domain_validation_options_local_provider = flatten(aws_acm_certificate.local_provider.*.domain_validation_options)
}

resource "aws_route53_record" "certificate_validation_local_provider" {
  count = length(local.endpoints_local_provider_gen_cert)

  zone_id = data.aws_route53_zone.local_provider_gen_cert.*.id[count.index]
  name    = local.domain_validation_options_local_provider[count.index]["resource_record_name"]
  type    = local.domain_validation_options_local_provider[count.index]["resource_record_type"]
  records = [local.domain_validation_options_local_provider[count.index]["resource_record_value"]]
  ttl     = 60

  allow_overwrite = true
}

locals {
  validation_record_fqdns_local_provider = flatten(
    aws_route53_record.certificate_validation_local_provider.*.fqdn,
  )
}

resource "aws_acm_certificate_validation" "local_provider" {
  count = length(local.endpoints_local_provider_gen_cert)

  certificate_arn         = aws_acm_certificate.local_provider[count.index].arn
  validation_record_fqdns = [local.validation_record_fqdns_local_provider[count.index]]
}

