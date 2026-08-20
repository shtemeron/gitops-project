terraform {
  required_version = ">= 1.11.0"
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Auth is exec-based via `aws eks get-token`, shelling out to the AWS CLI
# directly — no Terraform `aws` provider needed here at all, since nothing
# in this config manages an actual AWS resource.
provider "kubectl" {
  host                   = data.terraform_remote_state.infra.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.eks_cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infra.outputs.eks_cluster_name, "--region", var.aws_region]
  }
}
