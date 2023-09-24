variable "region" {
  default = "eu-north-1"

}

provider "aws" {
  region = var.region
  shared_credentials_files = ["~/.aws/credentials"]
  profile = "production"
}

resource "aws_iam_role" "ntt_lambda_role" {
  name   = "NTT_lambda_mailing_list_subscribe"
  tags = {"business_unit":"NTT"}
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "lambda.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_policy" "ntt_iam_policy_for_lambda" { 
  name         = "aws_iam_policy_for_terraform_aws_lambda_role"
  
  path         = "/"
  description  = "AWS IAM Policy for managing aws lambda role"
  policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
     "Resource": "arn:aws:logs:*:*:*",
     "Effect": "Allow"
   }
 ]
}
EOF
}

resource "aws_dynamodb_table" "ntt_maillist" {

  name           = "ntt_maillist"
  billing_mode   = "PROVISIONED"
  hash_key       = "email"
  
  tags = {"business_unit":"NTT",Environment = "production"}
  attribute {
    name = "email"
    type = "S"
  }
  
  write_capacity=1
  read_capacity=1
}
 
resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role        = aws_iam_role.ntt_lambda_role.name
  policy_arn  = aws_iam_policy.ntt_iam_policy_for_lambda.arn
}
 
data "archive_file" "zip_the_python_code" {
  type        = "zip"
  source_dir  = "${path.module}/python/"
  output_path = "${path.module}/python/ntt-python.zip"
}
 
resource "aws_lambda_function" "ntt_lambda_subscription" {
  tags = {"business_unit":"NTT"}
  filename                       = "${path.module}/python/ntt-python.zip"
  function_name                  = "ntt_lambda_function_mailing_list_subscribe"
  role                           = aws_iam_role.ntt_lambda_role.arn
  handler                        = "subscription.lambda_handler"
  runtime                        = "python3.11"
  depends_on                     = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
}

resource "aws_api_gateway_rest_api" "ntt_api" {
  tags = {"business_unit":"NTT"}
  name = "ntt_api_gateway"
  description = "Proxy to handle requests to our NTT API"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
}
resource "aws_api_gateway_request_validator" "ntt_validator" {
  name                        = "NTT Validate query string parameters and headers"
  rest_api_id                 = aws_api_gateway_rest_api.ntt_api.id
  validate_request_body       = false
  validate_request_parameters = true
  
}

resource "aws_api_gateway_method" "ntt_post_method" {
  
  rest_api_id   = aws_api_gateway_rest_api.ntt_api.id
  resource_id   = aws_api_gateway_rest_api.ntt_api.root_resource_id
  http_method   = "POST"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.proxy" = true
    "method.request.querystring.email" = true
    "method.request.querystring.name"  = true
  }
  request_validator_id = aws_api_gateway_request_validator.ntt_validator.id
  
}


resource "aws_api_gateway_integration" "ntt_lambda_subscription_integration" {
  rest_api_id = aws_api_gateway_rest_api.ntt_api.id
  resource_id = aws_api_gateway_rest_api.ntt_api.root_resource_id
  http_method = aws_api_gateway_method.ntt_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.ntt_lambda_subscription.invoke_arn}"
}

resource "aws_api_gateway_method_response" "ntt_response_200" {
  rest_api_id   = "${aws_api_gateway_rest_api.ntt_api.id}"
  resource_id   = "${aws_api_gateway_rest_api.ntt_api.root_resource_id}"
  http_method = aws_api_gateway_method.ntt_post_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
    
  }
  response_models = {
    "application/json" = "Empty"
  }
}