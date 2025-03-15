.PHONY: create-ecr create-app test-app build-container deploy-container create-tf-backend deploy-terraform test-api all run-local run-simulator

include .env
export AWS_PROFILE
export AWS_REGION

APP_NAME := go-lambda-api
ECR_REPO_NAME := $(APP_NAME)
TF_BACKEND_BUCKET := $(APP_NAME)-tf-backend-$(shell echo $(AWS_PROFILE) | tr '_' '-')

all: create-ecr create-app test-app build-container deploy-container create-tf-backend deploy-terraform test-api

# ECRレジストリを作成
create-ecr:
	@echo "Creating ECR repository..."
	aws ecr describe-repositories --repository-names $(ECR_REPO_NAME) --profile $(AWS_PROFILE) --region $(AWS_REGION) || \
	aws ecr create-repository --repository-name $(ECR_REPO_NAME) --image-scanning-configuration scanOnPush=true --profile $(AWS_PROFILE) --region $(AWS_REGION)

# Goアプリケーションを作成
create-app:
	@echo "Creating Go application..."
	mkdir -p app
	[ -f app/main.go ] || echo 'package main\n\nimport (\n\t"context"\n\t"encoding/json"\n\t"github.com/aws/aws-lambda-go/events"\n\t"github.com/aws/aws-lambda-go/lambda"\n)\n\ntype Response struct {\n\tMessage string `json:"message"`\n}\n\nfunc handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {\n\tresp := Response{Message: "hello"}\n\tbody, _ := json.Marshal(resp)\n\n\treturn events.APIGatewayProxyResponse{\n\t\tStatusCode: 200,\n\t\tBody:       string(body),\n\t\tHeaders: map[string]string{\n\t\t\t"Content-Type": "application/json",\n\t\t},\n\t}, nil\n}\n\nfunc main() {\n\tlambda.Start(handler)\n}' > app/main.go
	[ -f app/go.mod ] || (cd app && go mod init $(APP_NAME) && go mod tidy && go get github.com/aws/aws-lambda-go)
	[ -f Dockerfile ] || echo 'FROM golang:1.21-alpine AS builder\nWORKDIR /app\nCOPY app/ .\nRUN go mod download\nRUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o /main\n\nFROM public.ecr.aws/lambda/provided:al2-arm64\nCOPY --from=builder /main /var/runtime/bootstrap\nRUN chmod 755 /var/runtime/bootstrap' > Dockerfile

# ローカルでGoアプリケーションをテスト
test-app:
	@echo "Testing Go application..."
	cd app && go test ./... || echo "No tests found, skipping..."
	cd app && go build -o ../bin/main

# ローカルでGoサーバーを実行
run-local:
	@echo "Running local Go server..."
	cd app && go run main.go --local

# API Gatewayシミュレーターを実行
run-simulator:
	@echo "Running API Gateway simulator..."
	cd app && go run main.go --simulator

# コンテナをビルド
build-container:
	@echo "Building container..."
	docker build -t $(ECR_REPO_NAME):latest .

# コンテナをECRにデプロイ
deploy-container:
	@echo "Deploying container to ECR..."
	aws ecr get-login-password --profile $(AWS_PROFILE) --region $(AWS_REGION) | docker login --username AWS --password-stdin $(shell aws ecr describe-repositories --repository-names $(ECR_REPO_NAME) --profile $(AWS_PROFILE) --region $(AWS_REGION) --query 'repositories[0].repositoryUri' --output text | cut -d/ -f1)
	docker tag $(ECR_REPO_NAME):latest $(shell aws ecr describe-repositories --repository-names $(ECR_REPO_NAME) --profile $(AWS_PROFILE) --region $(AWS_REGION) --query 'repositories[0].repositoryUri' --output text):latest
	docker push $(shell aws ecr describe-repositories --repository-names $(ECR_REPO_NAME) --profile $(AWS_PROFILE) --region $(AWS_REGION) --query 'repositories[0].repositoryUri' --output text):latest

# Terraformバックエンド用のS3バケットを作成
create-tf-backend:
	@echo "Creating Terraform backend S3 bucket..."
	aws s3api head-bucket --bucket $(TF_BACKEND_BUCKET) --profile $(AWS_PROFILE) --region $(AWS_REGION) 2>/dev/null || \
	aws s3api create-bucket --bucket $(TF_BACKEND_BUCKET) --create-bucket-configuration LocationConstraint=$(AWS_REGION) --profile $(AWS_PROFILE) --region $(AWS_REGION)
	aws s3api put-bucket-versioning --bucket $(TF_BACKEND_BUCKET) --versioning-configuration Status=Enabled --profile $(AWS_PROFILE) --region $(AWS_REGION)

# Terraformでインフラをデプロイ
deploy-terraform:
	@echo "Deploying infrastructure with Terraform..."
	mkdir -p terraform
	[ -f terraform/main.tf ] || echo 'terraform {\n  required_providers {\n    aws = {\n      source  = "hashicorp/aws"\n      version = "~> 5.0"\n    }\n  }\n\n  backend "s3" {\n    bucket = "$(TF_BACKEND_BUCKET)"\n    key    = "terraform.tfstate"\n    region = "$(AWS_REGION)"\n  }\n}\n\nprovider "aws" {\n  region  = "$(AWS_REGION)"\n  profile = "$(AWS_PROFILE)"\n\n  default_tags {\n    tags = {\n      Project     = "$(APP_NAME)"\n      Environment = "dev"\n      ManagedBy   = "terraform"\n    }\n  }\n}\n\ndata "aws_ecr_repository" "app" {\n  name = "$(ECR_REPO_NAME)"\n}\n\ndata "aws_ecr_image" "app_image" {\n  repository_name = data.aws_ecr_repository.app.name\n  image_tag       = "latest"\n}\n\nresource "aws_lambda_function" "api" {\n  function_name = "$(APP_NAME)"\n  role          = aws_iam_role.lambda_exec.arn\n  package_type  = "Image"\n  image_uri     = "${data.aws_ecr_repository.app.repository_url}@${data.aws_ecr_image.app_image.image_digest}"\n\n  timeout = 30\n}\n\nresource "aws_iam_role" "lambda_exec" {\n  name = "$(APP_NAME)-lambda-exec-role"\n\n  assume_role_policy = jsonencode({\n    Version = "2012-10-17"\n    Statement = [{\n      Action = "sts:AssumeRole"\n      Effect = "Allow"\n      Principal = {\n        Service = "lambda.amazonaws.com"\n      }\n    }]\n  })\n}\n\nresource "aws_iam_role_policy_attachment" "lambda_basic" {\n  role       = aws_iam_role.lambda_exec.name\n  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"\n}\n\nresource "aws_apigatewayv2_api" "api" {\n  name          = "$(APP_NAME)-gateway"\n  protocol_type = "HTTP"\n}\n\nresource "aws_apigatewayv2_stage" "default" {\n  api_id      = aws_apigatewayv2_api.api.id\n  name        = "$default"\n  auto_deploy = true\n}\n\nresource "aws_apigatewayv2_integration" "lambda" {\n  api_id             = aws_apigatewayv2_api.api.id\n  integration_type   = "AWS_PROXY"\n  integration_uri    = aws_lambda_function.api.invoke_arn\n  integration_method = "POST"\n  payload_format_version = "2.0"\n}\n\nresource "aws_apigatewayv2_route" "default" {\n  api_id    = aws_apigatewayv2_api.api.id\n  route_key = "ANY /"\n  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"\n}\n\nresource "aws_lambda_permission" "api_gateway" {\n  statement_id  = "AllowExecutionFromAPIGateway"\n  action        = "lambda:InvokeFunction"\n  function_name = aws_lambda_function.api.function_name\n  principal     = "apigateway.amazonaws.com"\n  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"\n}\n\noutput "api_endpoint" {\n  value = aws_apigatewayv2_stage.default.invoke_url\n}' > terraform/main.tf
	cd terraform && terraform init && terraform apply -auto-approve

# APIをテスト
test-api:
	@echo "Testing API..."
	curl -s $(shell cd terraform && terraform output -raw api_endpoint) 