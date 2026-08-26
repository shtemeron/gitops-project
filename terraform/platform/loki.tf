# Stage 9 — Loki's IRSA role. Loki itself (Helm chart) is installed via
# ArgoCD (k8s-apps/argocd-apps/loki.yaml), not Terraform — same
# reasoning as Kyverno/Karpenter: it isn't a GitOps bootstrapping
# prerequisite. Only the IAM role lives here, since IRSA needs infra/'s
# OIDC provider output, same pattern as every other IRSA role in this
# project (ESO, external-dns, LB Controller).

data "aws_iam_policy_document" "loki_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.infra.outputs.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.infra.outputs.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:loki:loki"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.infra.outputs.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "loki" {
  name               = "${var.project_name}-loki"
  assume_role_policy = data.aws_iam_policy_document.loki_assume.json
}

# Narrowly scoped to the one bucket this project has for Loki (created
# back in Stage 5, unused until now) — not s3:*, same least-privilege
# pattern as ESO (one secret) and external-dns (one zone).
data "aws_iam_policy_document" "loki_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${data.terraform_remote_state.infra.outputs.loki_bucket_name}"]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${data.terraform_remote_state.infra.outputs.loki_bucket_name}/*"]
  }
}

resource "aws_iam_role_policy" "loki_s3" {
  name   = "${var.project_name}-loki-s3"
  role   = aws_iam_role.loki.id
  policy = data.aws_iam_policy_document.loki_s3.json
}
