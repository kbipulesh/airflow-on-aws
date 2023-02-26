data "aws_caller_identity" "current" {}

# SSL Certificate
data "aws_acm_certificate" "cert" {
  domain   = "airflow.${var.stage}.pam.mckinsey.com"
  statuses = ["ISSUED"]
}


data "external" "my-ip" {
  program = ["bash", "-c", "curl -s 'https://api.ipify.org?format=json'"]
}


data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../../lambda"
  output_path = "../lambda.zip"
}