output "api_gateway_endpoint" {
  description = "HTTP API Gateway invoke URL for this region"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "dynamodb_table_name" {
  description = "DynamoDB GreetingLogs table name"
  value       = aws_dynamodb_table.greeting_logs.name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_task_definition_arn" {
  description = "ECS Task Definition ARN"
  value       = aws_ecs_task_definition.sns_publisher.arn
}

output "greeter_lambda_arn" {
  description = "Greeter Lambda ARN"
  value       = aws_lambda_function.greeter.arn
}

output "dispatcher_lambda_arn" {
  description = "Dispatcher Lambda ARN"
  value       = aws_lambda_function.dispatcher.arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}
