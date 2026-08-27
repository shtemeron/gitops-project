# Stage 10 — GitHub Actions' identity for pushing to ECR. Federated via
# GitHub's own OIDC provider, not static access keys stored as repo
# secrets — the same pattern as every other AWS-facing identity in this
# project (EKS's own OIDC for IRSA, the bastion's instance role).

data "tls_certificate" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_oidc.certificates[0].sha1_fingerprint]
}

# Trust scoped to this repo's main branch specifically — not the whole
# repo, and never a fork or PR branch. GitHub's OIDC token's "sub" claim
# encodes exactly which ref triggered the run, so this is a real,
# enforced restriction, not just documentation.
data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # GitHub's current default OIDC subject format includes immutable
      # numeric IDs alongside the names (repo/owner renames can't ever
      # invalidate or hijack this trust relationship) — confirmed
      # directly from a real decoded token for this repo, not assumed
      # from GitHub's older, simpler documented format
      # ("repo:owner/repo:ref:..."), which no longer matches reality.
      values = ["repo:shtemeron@51164085/gitops-project@1338349254:ref:refs/heads/main"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
}

# Narrowly scoped to ECR push on just this one repository —
# GetAuthorizationToken is an AWS IAM limitation, not a shortcut:
# that specific action has no resource-level scoping at all, account-wide
# by necessity. Everything else is scoped to the repo's own ARN.
data "aws_iam_policy_document" "github_actions_ecr" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.url_shortener.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  name   = "${var.project_name}-github-actions-ecr"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_ecr.json
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
