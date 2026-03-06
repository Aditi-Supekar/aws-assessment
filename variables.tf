variable "primary_region" {
  description = "Primary AWS region (Cognito + Compute)"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region (Compute only)"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "assessment"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "unleash-assessment"
}

variable "test_user_email" {
  description = "Test user email address for Cognito"
  type        = string
  default     = "aditisupekar2412@gmail.com"
}

variable "test_user_password" {
  description = "Test user password - pass via TF_VAR_test_user_password or terraform.tfvars"
  type        = string
  sensitive   = true
  # No default - must be supplied at runtime
}

variable "github_repo_url" {
  description = "GitHub repository URL for SNS payload (no .git suffix)"
  type        = string
  default     = "https://github.com/Aditi-Supekar/aws-assessment"

  validation {
    condition     = !endswith(var.github_repo_url, ".git")
    error_message = "github_repo_url must not end with .git — the SNS payload requires a clean URL."
  }
}

variable "verification_sns_topic_arn" {
  description = "Unleash live SNS Topic ARN for candidate verification"
  type        = string
  default     = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"

}

variable "vpc_cidr_primary" {
  description = "VPC CIDR block for primary region"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_cidr_secondary" {
  description = "VPC CIDR block for secondary region"
  type        = string
  default     = "10.1.0.0/16"
}

variable "greeter_image_uri" {
  description = "ECR image URI for the Greeter Lambda function"
  type        = string

  validation {
    condition     = var.greeter_image_uri != ""
    error_message = "greeter_image_uri must be set to a valid ECR image URI."
  }
}

variable "dispatcher_image_uri" {
  description = "ECR image URI for the Dispatcher Lambda function"
  type        = string

  validation {
    condition     = var.dispatcher_image_uri != ""
    error_message = "dispatcher_image_uri must be set to a valid ECR image URI."
  }
}


variable "greeter_image_uri_secondary" {
  description = "ECR image URI for Greeter Lambda in secondary region"
  type        = string
}

variable "dispatcher_image_uri_secondary" {
  description = "ECR image URI for Dispatcher Lambda in secondary region"
  type        = string
}