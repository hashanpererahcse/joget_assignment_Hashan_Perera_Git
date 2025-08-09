terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Optional: remote backend (S3 + DynamoDB). Uncomment and fill to use.
  # backend "s3" {
  #   bucket         = "your-tf-state-bucket"
  #   key            = "hybrid-poc/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "your-tf-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
