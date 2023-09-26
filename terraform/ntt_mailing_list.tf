variable "region" {
  default = "eu-north-1"
}
variable "accountId" {
  default = "929700548940"
}

terraform {
  backend "s3" {
    bucket = "doprdele-terraform-backend"
    key    = "ntt/mailling-list.tfstate"
    region = "eu-north-1"
    dynamodb_table="terraform-locks"
  }
}

provider "aws" {
  region = var.region
  shared_credentials_files = ["~/.aws/credentials"]
  profile = "production"
}

resource "aws_iam_role" "ntt_lambda_role" {
  name   = "NTT_lambda"
  tags = {"business_unit":"NTT"}
  assume_role_policy = jsonencode({
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
})
}

resource "aws_dynamodb_table" "terraform-locks" {
    name           = "terraform-locks"
    read_capacity  = 5
    write_capacity = 5
    hash_key       = "LockID"
    attribute {
        name = "LockID"
        type = "S"
    }
    tags = {
        "Name" = "DynamoDB Terraform State Lock Table"
    }
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
 

resource "aws_iam_policy" "ntt_iam_policy_for_lambda" { 
  name         = "aws_iam_policy_for_terraform_aws_lambda_role"
  
  path         = "/"
  description  = "AWS IAM Policy for managing aws lambda role"
  policy = jsonencode({

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
   },
   {
     "Effect": "Allow",
     "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem"
      ],
     "Resource": [aws_dynamodb_table.ntt_maillist.arn]
   }
 ]

})
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

resource "aws_api_gateway_rest_api" "ntt_maillist_api" {
  
  name = "ntt_maillist_api"
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

resource "aws_lambda_permission" "allow_apigateway" {
  
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.ntt_lambda_subscription.function_name}"
  principal     = "apigateway.amazonaws.com"
}


resource "aws_api_gateway_method" "ntt_post_method" {
  
  rest_api_id   = aws_api_gateway_rest_api.ntt_api.id
  resource_id   = aws_api_gateway_rest_api.ntt_api.root_resource_id
  http_method   = "POST"
  authorization = "NONE"
  request_parameters = {
    # "method.request.path.proxy" = true
    "method.request.querystring.email" = true
    "method.request.querystring.name"  = true
  }
  request_validator_id = aws_api_gateway_request_validator.ntt_validator.id
  
}


resource "aws_api_gateway_integration" "ntt_lambda_subscription_integration" {
  rest_api_id = aws_api_gateway_rest_api.ntt_api.id
  resource_id = aws_api_gateway_rest_api.ntt_api.root_resource_id
  http_method = aws_api_gateway_method.ntt_post_method.http_method
  content_handling        = "CONVERT_TO_TEXT"
  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = aws_lambda_function.ntt_lambda_subscription.invoke_arn
  
}




resource "aws_api_gateway_method_response" "ntt_response_200" {
  rest_api_id = aws_api_gateway_rest_api.ntt_api.id
  resource_id = aws_api_gateway_rest_api.ntt_api.root_resource_id
  http_method = aws_api_gateway_method.ntt_post_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
    
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_deployment" "ntt_gw_deployment" {
  rest_api_id = aws_api_gateway_rest_api.ntt_api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.ntt_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_api_gateway_method.ntt_post_method]
}

resource "aws_api_gateway_stage" "ntt_final_stage" {
  deployment_id = aws_api_gateway_deployment.ntt_gw_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.ntt_api.id
  stage_name    = "final"
}



resource "aws_sns_topic" "ntt_subscription_email_bounce" {
  name = "ntt-subscription-email-bounce"
}

resource "aws_sns_topic" "ntt_subscription_email_complaint" {
  name = "ntt-subscription-email-complaint"
}

resource "aws_sns_topic" "ntt_subscription_email_delivery" {
  name = "ntt-subscription-email-delivery"
}

resource "aws_ses_email_identity" "ntt_noreply" {
  email = "noreply@nightingaletunes.com"
}

resource "aws_ses_identity_notification_topic" "ntt_subscription_bounce" {
  topic_arn                = aws_sns_topic.ntt_subscription_email_bounce.arn
  notification_type        = "Bounce"
  identity                 = aws_ses_email_identity.ntt_noreply.arn
  include_original_headers = true
}


resource "aws_ses_identity_notification_topic" "ntt_subscription_complaint" {
  topic_arn                = aws_sns_topic.ntt_subscription_email_complaint.arn
  notification_type        = "Complaint"
  identity                 = aws_ses_email_identity.ntt_noreply.arn
  include_original_headers = true
}

resource "aws_ses_identity_notification_topic" "ntt_subscription_delivery" {
  topic_arn                = aws_sns_topic.ntt_subscription_email_delivery.arn
  notification_type        = "Delivery"
  identity                 = aws_ses_email_identity.ntt_noreply.arn
  include_original_headers = true
}

output "url" {
  value = aws_api_gateway_stage.ntt_final_stage.invoke_url
}
