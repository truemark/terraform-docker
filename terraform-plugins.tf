terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    lacework = {
      source = "lacework/lacework"
      version = "~> 1.0"
    }
  }
}
