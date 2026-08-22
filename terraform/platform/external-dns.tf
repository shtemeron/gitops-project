# --- IRSA role for external-dns, scoped to just the one private zone it
# manages — not route53:* across the account ---

data "aws_iam_policy_document" "external_dns_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.infra.outputs.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.infra.outputs.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.infra.outputs.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.project_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume.json
}

data "aws_iam_policy_document" "external_dns_route53" {
  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.terraform_remote_state.infra.outputs.route53_zone_id}"]
  }

  # ListHostedZones/ListResourceRecordSets don't support resource-level
  # ARN scoping in IAM at all — an AWS API limitation, not a shortcut here.
  statement {
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "external_dns_route53" {
  name   = "${var.project_name}-external-dns-route53"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns_route53.json
}

# --- external-dns itself ---

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "external-dns"
  create_namespace = true

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }

  set {
    name  = "provider"
    value = "aws"
  }

  # Only watches Service resources for now (Postgres's headless Service,
  # Stage 5) — Gateway API sourcing for the app's public endpoint is
  # Stage 6's job, not added here ahead of need.
  set {
    name  = "txtOwnerId"
    value = var.project_name
  }

  set {
    name  = "domainFilters[0]"
    value = data.terraform_remote_state.infra.outputs.route53_zone_domain
  }

  set {
    name  = "policy"
    value = "sync"
  }
}
