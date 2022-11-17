locals {
  name      = "${var.project_name}-${var.environment}"
  base_path = var.project_name

  lambdas = {
    "create" = {
      path    = "${local.base_path}"
      method  = "POST"
      handler = "todos/create.create"
      cors    = true
    },
    "list" = {
      path    = "${local.base_path}"
      method  = "GET"
      handler = "todos/list.list"
    },
    "get" = {
      path    = "{id}"
      method  = "GET"
      handler = "todos/get.get"
      cors    = true
    },
    "update" = {
      path    = "{id}"
      method  = "PUT"
      handler = "todos/update.update"
      cors    = true
    },
    "delete" = {
      path    = "{id}"
      method  = "DELETE"
      handler = "todos/delete.delete"
      cors    = true
    }
  }

  lambdas_keys = [ for k, v in local.lambdas: k ]
}


data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "todos"
  output_path = "lambda.zip"
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${local.name}-lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_policy" "lambda_access_policy" {
  name = "${local.name}-lambda_access_policy"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan",
                "dynamodb:Query",
                "dynamodb:UpdateItem"
            ],
            "Resource": "${aws_dynamodb_table.todos.arn}"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_access_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_access_policy.arn
}


resource "aws_lambda_function" "todos" {

  for_each = {
    for k, v in local.lambdas :
    k => v
  }

  filename         = "lambda.zip"
  function_name    = "${local.name}-${each.key}"
  role             = aws_iam_role.lambda_role.arn
  handler          = each.value.handler
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.8"

  environment {
    variables = {
      DYNAMODB_TABLE = "${local.name}"
    }
  }
}

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

