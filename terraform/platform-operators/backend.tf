terraform {
  backend "s3" {
    bucket       = "gitops-project-tfstate-100282333708"
    key          = "gitops-project/platform-operators/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
