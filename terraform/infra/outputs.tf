output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca_certificate" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  value = aws_iam_openid_connect_provider.eks.url
}

output "db_credentials_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion_ssh_command" {
  value = "ssh -i ~/.ssh/gitops-project-bastion ec2-user@${aws_instance.bastion.public_ip}"
}

output "loki_bucket_name" {
  value = aws_s3_bucket.loki.id
}

output "route53_zone_id" {
  value = aws_route53_zone.internal.zone_id
}

output "route53_zone_domain" {
  value = aws_route53_zone.internal.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.url_shortener.repository_url
}

output "dev_acm_certificate_arn" {
  value = aws_acm_certificate.dev.arn
}

output "prod_acm_certificate_arn" {
  value = aws_acm_certificate.prod.arn
}

output "karpenter_node_role_arn" {
  value = aws_iam_role.eks_node.arn
}

output "karpenter_node_role_name" {
  value = aws_iam_role.eks_node.name
}

output "karpenter_interruption_queue_name" {
  value = aws_sqs_queue.karpenter_interruption.name
}

output "karpenter_interruption_queue_arn" {
  value = aws_sqs_queue.karpenter_interruption.arn
}
