data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_key_pair" "bastion" {
  key_name   = "${var.project_name}-bastion"
  public_key = file(pathexpand(var.bastion_public_key_path))
}

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion"
  description = "Bastion - SSH access (key-pair auth only)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion"
  }
}

data "aws_iam_policy_document" "bastion_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "${var.project_name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.bastion_assume.json
}

# Only what's needed to fetch a kubeconfig / get a cluster token — the actual
# in-cluster authorization comes from the EKS access entry in eks.tf, not IAM.
data "aws_iam_policy_document" "bastion_eks_describe" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }
}

resource "aws_iam_role_policy" "bastion_eks_describe" {
  name   = "${var.project_name}-bastion-eks-describe"
  role   = aws_iam_role.bastion.id
  policy = data.aws_iam_policy_document.bastion_eks_describe.json
}

# From Stage 3 on, `terraform apply` runs from the bastion against the same
# state as everything else — refreshing that state means reading every
# existing resource, not just the new ones this stage creates. Broad
# read-only access (AWS managed ReadOnlyAccess) covers that refresh; actual
# write/create permission stays narrowly scoped below, so a compromised
# bastion can see the account but can't mutate anything outside its lane.
resource "aws_iam_role_policy_attachment" "bastion_read_only" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Write access, narrowly scoped: the Terraform state object itself, and IAM
# role management restricted to roles this project creates (e.g. Stage 3's
# ESO IRSA role) — not arbitrary IAM in the account.
data "aws_iam_policy_document" "bastion_terraform_write" {
  statement {
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "arn:aws:s3:::gitops-project-tfstate-${data.aws_caller_identity.current.account_id}/*",
    ]
  }

  statement {
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*"]
  }
}

resource "aws_iam_role_policy" "bastion_terraform_write" {
  name   = "${var.project_name}-bastion-terraform-write"
  role   = aws_iam_role.bastion.id
  policy = data.aws_iam_policy_document.bastion_terraform_write.json
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-bastion"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  key_name               = aws_key_pair.bastion.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    dnf install -y git unzip

    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl

    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh

    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    dnf install -y terraform

    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    unzip -q awscliv2.zip
    ./aws/install --update
    rm -rf awscliv2.zip aws

    sudo -u ec2-user aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}
  EOF

  tags = {
    Name = "${var.project_name}-bastion"
  }

  depends_on = [
    aws_eks_access_entry.bastion,
    aws_eks_access_policy_association.bastion_admin,
  ]
}
