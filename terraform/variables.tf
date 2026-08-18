variable "project_name" {
  type    = string
  default = "gitops-project"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# One AZ per element — index 0 backs public-a/private-a, index 1 backs public-b/private-b.
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "eks_version" {
  type        = string
  default     = "1.36"
  description = "Pinned explicitly rather than left floating — verified as the latest EKS-supported version at design time via `aws eks describe-addon-versions`."
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "bastion_allowed_ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH into the bastion. No default — set in terraform.tfvars (gitignored, environment-specific, not this file)."
}

variable "bastion_public_key_path" {
  type        = string
  description = "Path to the bastion's SSH public key. No default — set in terraform.tfvars."
}
