# IMMUTABLE tags: forces every build to get a genuinely new, traceable
# tag instead of silently overwriting one (e.g. "latest") — Stage 10's CI
# will tag by run number + short SHA for exactly this reason.
resource "aws_ecr_repository" "url_shortener" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"
  # Without this, AWS rejects deleting a non-empty repository outright —
  # `terraform destroy` would halt on this resource specifically rather
  # than completing, undermining the repeated destroy/rebuild cycles
  # this project is built around.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
