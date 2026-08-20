# --- IRSA role for ESO, created before the Helm release so its ARN can be
# passed straight into the chart's service-account annotation ---

data "aws_iam_policy_document" "eso_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.infra.outputs.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.infra.outputs.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.infra.outputs.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project_name}-eso"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

# Narrowly scoped to the one secret this project has — not secretsmanager:*.
data "aws_iam_policy_document" "eso_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [data.terraform_remote_state.infra.outputs.db_credentials_secret_arn]
  }
}

resource "aws_iam_role_policy" "eso_secrets" {
  name   = "${var.project_name}-eso-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_secrets.json
}

# --- ESO itself ---

resource "helm_release" "eso" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.eso.arn
  }
}

# helm_release reports done once Helm submits the install — the API
# server's discovery cache can lag behind actually recognizing the CRDs
# that install just created, by a variable amount (a fixed sleep proved
# unreliable in practice — 20s wasn't always enough). Actively wait until
# the CRD is genuinely Established instead of guessing a delay.
resource "null_resource" "wait_for_eso_crds" {
  depends_on = [helm_release.eso]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Established --timeout=120s crd/clustersecretstores.external-secrets.io"
  }
}

# --- Tells ESO how to reach AWS Secrets Manager ---

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secrets-manager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [null_resource.wait_for_eso_crds]
}
