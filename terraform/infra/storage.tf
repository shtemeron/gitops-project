# Loki's storage backend (Stage 9) — provisioned now alongside the other
# foundational resources, not consumed until the observability stage.
resource "aws_s3_bucket" "loki" {
  bucket = "${var.project_name}-loki-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Postgres credentials. Terraform owns only the empty secret container — never
# the version/value, which will be set manually and synced in via ESO in
# Stage 3. A Terraform-managed version drifts the moment anyone rotates the
# secret by hand; the container alone doesn't have that problem.
#
# recovery_window_in_days = 0: this project gets destroyed and rebuilt
# repeatedly (portfolio/demo use, not a production secret with real data to
# protect against accidental deletion) — the default 30-day recovery window
# otherwise blocks recreating a same-named secret on every rebuild until the
# window expires, exactly the failure this project hit once already.
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/db-credentials"
  recovery_window_in_days = 0
}
