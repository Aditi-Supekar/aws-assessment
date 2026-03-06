# ============================================================================
# VPC — Public subnets only (avoids NAT Gateway charges)
# ============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc-${var.region}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw-${var.region}"
  }
}

# Two public subnets across two AZs for ECS Fargate task placement
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-a-${var.region}"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-b-${var.region}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-public-${var.region}"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Security group for ECS Fargate — allow outbound HTTPS to reach SNS
resource "aws_security_group" "ecs_task" {
  name        = "${var.project_name}-ecs-sg-${var.region}"
  description = "Allow ECS Fargate task outbound HTTPS only"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for SNS publish"
  }

  tags = {
    Name = "${var.project_name}-ecs-sg-${var.region}"
  }
}

# ============================================================================
# DYNAMODB TABLE — Regional GreetingLogs
# ============================================================================

resource "aws_dynamodb_table" "greeting_logs" {
  name         = "${var.project_name}-GreetingLogs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-GreetingLogs-${var.region}"
  }
}

# ============================================================================
# LAMBDA — Greeter
# ============================================================================

resource "aws_lambda_function" "greeter" {
  function_name = "${var.project_name}-greeter-${var.region}"
  role          = aws_iam_role.lambda_greeter.arn
  package_type  = "Image"
  image_uri     = var.greeter_image_uri
  timeout       = 30
  memory_size   = 128

  environment {
    variables = {
      REGION          = var.region
      DYNAMODB_TABLE  = aws_dynamodb_table.greeting_logs.name
      SNS_TOPIC_ARN   = var.sns_topic_arn
      TEST_USER_EMAIL = var.test_user_email
      GITHUB_REPO_URL = var.github_repo_url
    }
  }

  tags = {
    Name = "${var.project_name}-greeter-${var.region}"
  }
}

# ============================================================================
# LAMBDA — Dispatcher
# ============================================================================

resource "aws_lambda_function" "dispatcher" {
  function_name = "${var.project_name}-dispatcher-${var.region}"
  role          = aws_iam_role.lambda_dispatcher.arn
  package_type  = "Image"
  image_uri     = var.dispatcher_image_uri
  timeout       = 60
  memory_size   = 128

  environment {
    variables = {
      REGION              = var.region
      ECS_CLUSTER_ARN     = aws_ecs_cluster.main.arn
      ECS_TASK_DEF_ARN    = aws_ecs_task_definition.sns_publisher.arn
      ECS_SUBNET_ID       = aws_subnet.public_a.id
      ECS_SECURITY_GRP_ID = aws_security_group.ecs_task.id
    }
  }

  tags = {
    Name = "${var.project_name}-dispatcher-${var.region}"
  }
}

# ============================================================================
# ECS CLUSTER
# ============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster-${var.region}"

  setting {
    name  = "containerInsights"
    value = "disabled" # disabled to save cost for assessment
  }

  tags = {
    Name = "${var.project_name}-cluster-${var.region}"
  }
}

# ============================================================================
# ECS TASK DEFINITION — SNS Publisher (uses amazon/aws-cli image)
# ============================================================================

resource "aws_ecs_task_definition" "sns_publisher" {
  family                   = "${var.project_name}-sns-publisher-${var.region}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "sns-publisher"
      image = "amazon/aws-cli:latest"

      # Publishes the ECS verification payload to Unleash live SNS topic then exits
      command = [
        "sns", "publish",
        "--topic-arn", var.sns_topic_arn,
        "--region", "us-east-1",
        "--message", jsonencode({
          email  = var.test_user_email
          source = "ECS"
          region = var.region
          repo   = var.github_repo_url
        })
      ]

      environment = [
        { name = "AWS_DEFAULT_REGION", value = var.region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}-${var.region}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "sns-publisher"
          "awslogs-create-group"  = "true"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-sns-publisher-${var.region}"
  }
}

# ============================================================================
# API GATEWAY — HTTP API with Cognito Authorizer
# ============================================================================

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api-${var.region}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
  }

  tags = {
    Name = "${var.project_name}-api-${var.region}"
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  name             = "${var.project_name}-cognito-authorizer"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [var.cognito_app_client_id]
    issuer   = "https://cognito-idp.us-east-1.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# Lambda permissions for API Gateway to invoke
resource "aws_lambda_permission" "apigw_greeter" {
  statement_id  = "AllowAPIGatewayInvokeGreeter"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_dispatcher" {
  statement_id  = "AllowAPIGatewayInvokeDispatcher"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Lambda integrations
resource "aws_apigatewayv2_integration" "greeter" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.greeter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "dispatcher" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.invoke_arn
  payload_format_version = "2.0"
}

# Routes — secured with Cognito JWT authorizer
resource "aws_apigatewayv2_route" "greet" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /greet"
  target             = "integrations/${aws_apigatewayv2_integration.greeter.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "dispatch" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /dispatch"
  target             = "integrations/${aws_apigatewayv2_integration.dispatcher.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

# Stage — auto-deploy
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Name = "${var.project_name}-stage-${var.region}"
  }
}
