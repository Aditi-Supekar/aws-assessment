# ============================================================================
# IAM — Lambda Greeter Execution Role
# ============================================================================

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_greeter" {
  name               = "${var.project_name}-greeter-role-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_greeter_policy" {
  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/lambda/*"]
  }

  # DynamoDB — regional table only
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = ["arn:aws:dynamodb:${var.region}:*:table/${var.project_name}-GreetingLogs"]
  }

  # SNS Publish — cross-region to us-east-1 Unleash live topic
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_role_policy" "lambda_greeter" {
  name   = "${var.project_name}-greeter-policy"
  role   = aws_iam_role.lambda_greeter.id
  policy = data.aws_iam_policy_document.lambda_greeter_policy.json
}

# ============================================================================
# IAM — Lambda Dispatcher Execution Role
# ============================================================================

resource "aws_iam_role" "lambda_dispatcher" {
  name               = "${var.project_name}-dispatcher-role-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_dispatcher_policy" {
  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/lambda/*"]
  }

  # ECS RunTask
  statement {
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = [aws_ecs_task_definition.sns_publisher.arn]
  }

  # PassRole — allow Lambda to pass the ECS task role to ECS
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_task_role.arn,
      aws_iam_role.ecs_task_execution_role.arn
    ]
  }
}

resource "aws_iam_role_policy" "lambda_dispatcher" {
  name   = "${var.project_name}-dispatcher-policy"
  role   = aws_iam_role.lambda_dispatcher.id
  policy = data.aws_iam_policy_document.lambda_dispatcher_policy.json
}

# ============================================================================
# IAM — ECS Task Execution Role (pull image, write logs)
# ============================================================================

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.project_name}-ecs-exec-role-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ============================================================================
# IAM — ECS Task Role (what the container can DO — publish SNS)
# ============================================================================

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-ecs-task-role-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_policy" {
  # SNS Publish cross-region to Unleash live topic
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_role" {
  name   = "${var.project_name}-ecs-task-policy"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ecs_task_policy.json
}
