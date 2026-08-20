# Read-only pointer at infra/'s state — never applies or modifies it. This
# is how platform/ learns the cluster endpoint, OIDC provider, and secret
# ARN without infra/'s resources living in this state at all.
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "gitops-project-tfstate-100282333708"
    key    = "gitops-project/infra/terraform.tfstate"
    region = "us-east-1"
  }
}
