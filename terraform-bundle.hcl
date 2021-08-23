terraform {
  # Version of Terraform to include in the bundle. An exact version number is required.
  version = "TERRAFORM_VERSION"
}

# Define which provider plugins are to be included
providers {
  # https://registry.terraform.io/providers/hashicorp/aws/latest
  aws = {
    versions = [">=3.0"]
  }
}
