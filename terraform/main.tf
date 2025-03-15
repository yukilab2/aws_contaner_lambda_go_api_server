terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "pcafe_yukilab_tokyo"

  default_tags {
    tags = {
      Project     = "go-lambda-api"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_ecr_repository" "app" {
  name = "go-lambda-api"
}

data "aws_ecr_image" "app_image" {
  repository_name = data.aws_ecr_repository.app.name
  image_tag       = "latest"
}

resource "aws_lambda_function" "api" {
  function_name = "go-lambda-api"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.app.repository_url}@${data.aws_ecr_image.app_image.image_digest}"
  architectures = ["arm64"]

  timeout = 30
}

resource "aws_lambda_function_url" "api_url" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
    max_age       = 86400
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "go-lambda-api-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

output "lambda_url" {
  value = aws_lambda_function_url.api_url.function_url
}
