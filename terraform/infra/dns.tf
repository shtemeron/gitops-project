# Private hosted zone for internal service DNS — Stage 1's confirmed
# interpretation #2: the app resolves Postgres via a real custom name on
# a private Route 53 zone through external-dns, not bare Service DNS.
resource "aws_route53_zone" "internal" {
  name = "${var.project_name}.internal"

  vpc {
    vpc_id = aws_vpc.main.id
  }
}
