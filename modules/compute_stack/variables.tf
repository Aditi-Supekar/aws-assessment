variable "region" {
  description = "AWS region this compute stack is deployed into"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID (from us-east-1)"
  type        = string
}

variable "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN (from us-east-1) — used for API Gateway authorizer"
  type        = string
}

variable "test_user_email" {
  description = "Test user email for SNS payload"
  type        = string
}

variable "github_repo_url" {
  description = "GitHub repo URL for SNS payload"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for this region"
  type        = string
}

variable "sns_topic_arn" {
  description = "Unleash live SNS Topic ARN (us-east-1) — published to cross-region"
  type        = string
}

variable "greeter_image_uri" {
  description = "Container image URI for the Greeter Lambda"
  type        = string
}

variable "dispatcher_image_uri" {
  description = "Container image URI for the Dispatcher Lambda"
  type        = string
}

variable "cognito_app_client_id" {
  description = "Cognito User Pool App Client ID for JWT authorizer audience"
  type        = string
}