data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket           = format("lambda-bucket-%s-%s-an", data.aws_caller_identity.current.account_id, data.aws_region.current.region)
  bucket_namespace = "account-regional"
}


resource "aws_s3_bucket_ownership_controls" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

data "archive_file" "lambda_hello_world" {
  for_each = var.functions
  type = "zip"

  source_dir  = "../${path.module}/${each.value.source_dir}"
  output_path = "../${path.module}/${each.value.output_dir}"
}

resource "aws_s3_object" "lambda_hello_world" {
  for_each = var.functions

  bucket = aws_s3_bucket.lambda_bucket.id

  key    = each.value.output_dir
  source = data.archive_file.lambda_hello_world[each.key].output_path

  etag = filemd5(data.archive_file.lambda_hello_world[each.key].output_path)
}

resource "aws_lambda_function" "hello_world" {
  for_each = var.functions

  function_name = each.value.name

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_hello_world[each.key].key

  runtime = "nodejs24.x"
  handler = "${each.key}.handler"

  source_code_hash = data.archive_file.lambda_hello_world[each.key].output_base64sha256

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_cloudwatch_log_group" "hello_world" {
  for_each = var.functions

  name = "/aws/lambda/${aws_lambda_function.hello_world[each.key].function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "serverless_lambda_exec_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "v2"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "hello_world" {
  for_each = var.functions

  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.hello_world[each.key].invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "hello_world" {
  for_each = var.functions

  api_id = aws_apigatewayv2_api.lambda.id

  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.hello_world[each.key].id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  for_each = var.functions

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world[each.key].function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}


