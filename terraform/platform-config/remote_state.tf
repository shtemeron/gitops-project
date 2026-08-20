# Read-only pointer at infra/'s state — never applies or modifies it.
# Deliberately no pointer at platform-operators/'s state: nothing here
# needs a direct Terraform reference to ArgoCD/ESO's resources, only the
# fact that they already exist in the cluster (by the time this config is
# ever applied, in a separate, later `terraform apply` invocation).
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "gitops-project-tfstate-100282333708"
    key    = "gitops-project/infra/terraform.tfstate"
    region = "us-east-1"
  }
}
