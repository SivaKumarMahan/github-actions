terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial backend configuration. Bucket, key and region are passed at init time:
  #   tofu init -backend-config="bucket=<state-bucket>" \
  #             -backend-config="key=project3/staging.tfstate" \
  #             -backend-config="region=us-east-1"
  # use_lockfile = S3 native state locking (no DynamoDB table needed).
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.name
      Environment = var.environment
      ManagedBy   = "opentofu"
      Repository  = var.github_repository
    }
  }
}
