# IMMUTABLE tags: forces every build to get a genuinely new, traceable
# tag instead of silently overwriting one (e.g. "latest") — Stage 10's CI
# will tag by run number + short SHA for exactly this reason.
resource "aws_ecr_repository" "url_shortener" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
