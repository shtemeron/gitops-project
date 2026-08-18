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
  description = "Bastion — SSH from a known CIDR only"
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
