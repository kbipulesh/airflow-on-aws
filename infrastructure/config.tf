variable "aws_region" {
  default = "us-east-1"
}

variable "aws_profile" {
  default = "default"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "project_name" {
  default = "my-airflow"
}

variable "stage" {
  default = "qa"
}

variable "base_cidr_block" {
  default = "10.0.0.0"
}

variable "log_group_name" {
  default = "ecs/fargate"
}

variable "image_version" {
  default = "latest"
}

variable "metadata_db_instance_type" {
  default = "db.t3.micro"
}

variable "celery_backend_instance_type" {
  default = "cache.t2.small"
}