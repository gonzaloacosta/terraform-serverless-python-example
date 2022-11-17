# API Gateway Rest API 
resource "aws_api_gateway_rest_api" "apigw" {

  name = "${local.name}-apigateway"

}

# API Gateway Resources 
resource "aws_api_gateway_resource" "main" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  parent_id   = aws_api_gateway_rest_api.apigw.root_resource_id
  path_part   = local.base_path
}

resource "aws_api_gateway_resource" "todo_id" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  parent_id   = aws_api_gateway_resource.main.id
  path_part   = "{id}"

}

# API Gateway Methods
resource "aws_api_gateway_method" "todos" {

  for_each = {
    for k, v in local.lambdas :
    k => v
  }

  rest_api_id   = aws_api_gateway_rest_api.apigw.id
  resource_id   = each.value.path == local.base_path ? aws_api_gateway_resource.main.id : aws_api_gateway_resource.todo_id.id
  http_method   = each.value.method
  authorization = "NONE"

}

# API Gateway Integration
resource "aws_api_gateway_integration" "todos" {

  for_each = {
    for k, v in local.lambdas :
    k => v
  }

  rest_api_id             = aws_api_gateway_rest_api.apigw.id
  resource_id             = each.value.path == local.base_path ? aws_api_gateway_resource.main.id : aws_api_gateway_resource.todo_id.id
  http_method             = aws_api_gateway_method.todos[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.todos[each.key].invoke_arn
}

# API Gateway Deployment

resource "aws_api_gateway_deployment" "todos" {

  depends_on = [
    aws_api_gateway_integration.todos["create"],
    aws_api_gateway_integration.todos["list"],
    aws_api_gateway_integration.todos["get"],
    aws_api_gateway_integration.todos["update"],
    aws_api_gateway_integration.todos["delete"]
  ]
  
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  stage_name  = var.environment

}

# Allow API Gateway To Access Lambda

resource "aws_lambda_permission" "apigw-to-lambdas" {

  for_each = {
    for k, v in local.lambdas :
    k => v
  }

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todos[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${aws_api_gateway_rest_api.apigw.id}/*/*"
}

