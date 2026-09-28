# The tag value that AWS Backup (Task 19) uses to find resources.
locals {
  project_tag = "depi-mini-project-1"
}

provider "aws" {
  region = var.region

  # Set once here. Every resource that supports tags gets these automatically.
  default_tags {
    tags = {
      Project     = local.project_tag
      Owner       = var.owner
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }
}
