# provider
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

provider "external" {}

provider "archive" {
  # Configuration options
}
