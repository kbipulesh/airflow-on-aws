# Airflow Config
resource "aws_secretsmanager_secret" "fernet_key" {
  name        = "${var.project_name}-${var.stage}/config/airflow-fernet-key"
  description = "Fernet key for ${var.project_name}-${var.stage}"
}

resource "aws_secretsmanager_secret" "ws_secret_key" {
  name        = "${var.project_name}-${var.stage}/config/airflow-webserver-secret-key"
  description = "Secret key for ${var.project_name}-${var.stage}"
}

resource "aws_secretsmanager_secret" "okta_config" {
  name        = "${var.project_name}-${var.stage}/config/airflow-okta-config"
  description = "OKTA details for ${var.project_name}-${var.stage}"
}

resource "aws_secretsmanager_secret" "postgres_db" {
  name        = "${var.project_name}-${var.stage}/config/postgres-db"
  description = "Access to metadata database for ${var.project_name}-${var.stage}"
}

resource "aws_secretsmanager_secret_version" "postgres_db" {
  secret_id     = aws_secretsmanager_secret.postgres_db.id
  secret_string = <<EOF
    {
      "username": "airflow",
      "password": "${random_string.metadata_db_password.result}",
      "engine": "postgres",
      "host": "${aws_db_instance.metadata_db.address}",
      "port": "5432",
      "dbname": "airflow",
      "dbInstanceIdentifier": "${var.project_name}-${var.stage}-postgres"
    }
    EOF

  version_stages = ["AWSCURRENT"]
}

resource "aws_secretsmanager_secret" "postgres_db_cred" {
  name        = "${var.project_name}-${var.stage}/config/postgres-db-password"
  description = "Credentials of metadata database for ${var.project_name}-${var.stage}"
}

resource "aws_secretsmanager_secret_version" "postgres_db_cred" {
  secret_id     = aws_secretsmanager_secret.postgres_db_cred.id
  secret_string = random_string.metadata_db_password.result
}

resource "aws_secretsmanager_secret" "smtp_config" {
  name        = "${var.project_name}-${var.stage}/config/smtp-config"
  description = "SMTP configuration for ${var.project_name}-${var.stage}"
}


# Connections
resource "aws_secretsmanager_secret" "aws_conn_mail" {
  name        = "${var.project_name}-${var.stage}/connections/aws-mail"
  description = "AWS connection details for Airflow Email Config"
}

# Variables
resource "aws_secretsmanager_secret" "qualtrics_config" {
  name        = "${var.project_name}-${var.stage}/variables/qualtrics"
  description = "Qualtrics config"
}
