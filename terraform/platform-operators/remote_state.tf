# Read-only pointer at infra/'s state — never applies or modifies it.
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "gitops-project-tfstate-100282333708"
    key    = "gitops-project/infra/terraform.tfstate"
    region = "us-east-1"
  }
}
