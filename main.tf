terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary region provider (us-east-1)
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# Secondary region provider (eu-west-1)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# ============================================================================
# COGNITO USER POOL (PRIMARY REGION ONLY - us-east-1)
# ============================================================================

resource "aws_cognito_user_pool" "main" {
  provider = aws.primary
  name     = "${var.project_name}-user-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  tags = {
    Name = "${var.project_name}-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "main" {
  provider        = aws.primary
  user_pool_id    = aws_cognito_user_pool.main.id
  name     = "${var.project_name}-client"
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # ENABLED prevents user enumeration attacks
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user" "test_user" {
  provider       = aws.primary
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = var.test_user_email
  password       = var.test_user_password
  message_action = "SUPPRESS"

  attributes = {
    email          = var.test_user_email
    email_verified = true
  }
}

# ============================================================================
# COMPUTE STACK - MULTI-REGION MODULE
# ============================================================================

module "compute_stack_primary" {
  providers = {
    aws = aws.primary
  }

  source = "./modules/compute_stack"

  region               = var.primary_region
  project_name         = var.project_name
  environment          = var.environment
  cognito_user_pool_id = aws_cognito_user_pool.main.id
  cognito_user_pool_arn = aws_cognito_user_pool.main.arn
  test_user_email      = var.test_user_email
  github_repo_url      = var.github_repo_url
  vpc_cidr             = var.vpc_cidr_primary
  sns_topic_arn        = var.verification_sns_topic_arn
  greeter_image_uri    = var.greeter_image_uri
  dispatcher_image_uri = var.dispatcher_image_uri

  depends_on = [aws_cognito_user_pool.main]
  cognito_app_client_id = aws_cognito_user_pool_client.main.id   # ← add this line
  


}

module "compute_stack_secondary" {
  providers = {
    aws = aws.secondary
  }

  source = "./modules/compute_stack"

  region               = var.secondary_region
  project_name         = var.project_name
  environment          = var.environment
  cognito_user_pool_id = aws_cognito_user_pool.main.id
  cognito_user_pool_arn = aws_cognito_user_pool.main.arn
  test_user_email      = var.test_user_email
  github_repo_url      = var.github_repo_url
  vpc_cidr             = var.vpc_cidr_secondary
  sns_topic_arn        = var.verification_sns_topic_arn
  greeter_image_uri    = var.greeter_image_uri_secondary
  dispatcher_image_uri = var.dispatcher_image_uri_secondary

  depends_on = [aws_cognito_user_pool.main]
  cognito_app_client_id = aws_cognito_user_pool_client.main.id   # ← add this line


}

# ============================================================================
# OUTPUTS
# ============================================================================

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "primary_api_endpoint" {
  description = "Primary region API Gateway endpoint"
  value       = module.compute_stack_primary.api_gateway_endpoint
}

output "secondary_api_endpoint" {
  description = "Secondary region API Gateway endpoint"
  value       = module.compute_stack_secondary.api_gateway_endpoint
}

output "primary_region" {
  value = var.primary_region
}

output "secondary_region" {
  value = var.secondary_region
}
