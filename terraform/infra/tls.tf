# Self-signed certs, imported directly into ACM — no owned domain, so no
# DNS validation flow. Separate cert (separate private key) per
# environment, consistent with the isolation theme elsewhere in this
# project: if dev's private key were ever exposed, it has no bearing on
# prod's TLS listener. Browser shows an untrusted-cert warning by design
# — a known, explainable tradeoff, not an oversight (ARCHITECTURE.md
# Stage 6).

resource "tls_private_key" "dev" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "dev" {
  private_key_pem = tls_private_key.dev.private_key_pem

  subject {
    common_name  = "dev.${var.project_name}.local"
    organization = var.project_name
  }

  dns_names = ["dev.${var.project_name}.local"]

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "dev" {
  private_key      = tls_private_key.dev.private_key_pem
  certificate_body = tls_self_signed_cert.dev.cert_pem
}

resource "tls_private_key" "prod" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "prod" {
  private_key_pem = tls_private_key.prod.private_key_pem

  subject {
    common_name  = "prod.${var.project_name}.local"
    organization = var.project_name
  }

  dns_names = ["prod.${var.project_name}.local"]

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "prod" {
  private_key      = tls_private_key.prod.private_key_pem
  certificate_body = tls_self_signed_cert.prod.cert_pem
}
