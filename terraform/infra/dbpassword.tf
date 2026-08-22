# Postgres credentials. Terraform owns the value from creation, not just
# the container — the real-world pattern here (matching how RDS + Secrets
# Manager native rotation actually works) is Terraform bootstraps the
# initial value, and ongoing rotation is either automated (a rotation
# Lambda, not applicable to a self-managed StatefulSet Postgres like this
# one) or explicitly NOT done by hand outside Terraform. The drift
# incident a prior project hit came from a human running
# `put-secret-value` on a Terraform-tracked secret — the fix isn't
# "Terraform never touches the value," it's "the value's owner is
# unambiguous." Since there's no rotation Lambda for this self-managed
# Postgres, that owner is Terraform: rotate by changing this config (e.g.
# `terraform apply -replace=random_password.db`), not by hand.
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

resource "random_password" "db" {
  length  = 24
  special = false # avoids shell/connection-string quoting headaches downstream
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "urlshortener"
    password = random_password.db.result
  })
}
