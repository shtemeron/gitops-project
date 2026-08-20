# Small, intentionally duplicated set shared with infra/'s variables.tf —
# these are stable, rarely-changing values, not business logic worth
# threading through a remote-state indirection.

variable "project_name" {
  type    = string
  default = "gitops-project"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type        = string
  default     = ""
  description = "Local AWS CLI profile name to use, if any. Empty by default — portable across machines. Set in terraform.tfvars, not here."
}
