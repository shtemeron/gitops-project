# Defensive safety net, not the actual fix — the real fix is this config
# being a genuinely separate `terraform apply` process from
# platform-operators/, which gives it its own fresh API discovery cache
# rather than a stale one from before ESO's CRD existed. This wait just
# covers the edge case of platform-operators and this config being applied
# back-to-back with barely any gap.
resource "null_resource" "wait_for_eso_crds" {
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
