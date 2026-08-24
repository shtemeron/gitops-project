resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  # Same race as eso.tf: this chart creates its own Services
  # (argocd-server, repo-server, etc.), which route through the LB
  # Controller's cluster-wide Service-mutating webhook once installed.
  # Depend on the controller finishing first so its webhook pod is
  # already Ready.
  depends_on = [helm_release.lb_controller]
}

# App-of-Apps root — the one manual/imperative apply in the whole system
# (ARCHITECTURE.md Stage 3). Points at an empty directory for now; later
# stages add child Application manifests there, and ArgoCD picks them up
# from a plain `git commit`, no further Terraform or kubectl involved.
resource "kubectl_manifest" "root_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/shtemeron/gitops-project.git"
        targetRevision = "main"
        path           = "k8s-apps/argocd-apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  })

  depends_on = [helm_release.argocd]
}
