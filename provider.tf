terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.61.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region     = "us-east-1"
  access_key = "AKIAWV6WULHJGHHV4TKV"
  secret_key = "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"
}
