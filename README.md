# Go Lambda Container API Server

このプロジェクトは、AWS Lambda上でコンテナ化されたGoアプリケーションを実行し、API Gatewayを通じて公開するサーバーレスAPIを提供します。

## 前提条件

- AWS CLI (設定済み)
- Docker
- Go 1.21以上
- Terraform
- Make

## 環境変数

`.env`ファイルに以下の環境変数を設定してください：

```
AWS_PROFILE=pcafe_yukilab_tokyo
AWS_REGION=ap-northeast-1
```

## 使い方

### 全てのステップを一度に実行

```bash
make all
```

### 個別のステップを実行

1. ECRリポジトリを作成

```bash
make create-ecr
```

2. Goアプリケーションを作成

```bash
make create-app
```

3. ローカルでGoアプリケーションをテスト

```bash
make test-app
```

4. ローカルでGoサーバーを実行

```bash
make run-local
```

サーバーが起動したら、ブラウザまたはcurlで `http://localhost:8080/` にアクセスできます。

```bash
curl http://localhost:8080/
```

5. API Gatewayシミュレーターを実行

```bash
make run-simulator
```

API Gatewayシミュレーターは、AWS Lambda関数をローカルで実行し、API Gatewayからのリクエストをシミュレートします。
これにより、AWS環境にデプロイする前に、Lambda関数の動作をデバッグできます。

```bash
# 基本的なGETリクエスト
curl http://localhost:8080/

# クエリパラメータを含むリクエスト
curl "http://localhost:8080/?param1=value1&param2=value2"

# POSTリクエスト
curl -X POST -H "Content-Type: application/json" -d '{"key":"value"}' http://localhost:8080/
```

6. コンテナをビルド

```bash
make build-container
```

7. コンテナをECRにデプロイ

```bash
make deploy-container
```

8. Terraformバックエンド用のS3バケットを作成

```bash
make create-tf-backend
```

9. Terraformでインフラをデプロイ

```bash
make deploy-terraform
```

10. APIをテスト

```bash
make test-api
```

## アーキテクチャ

- **言語**: Go
- **実行環境**: AWS Lambda (ARM64)
- **コンテナ**: カスタムコンテナイメージ
- **API**: Amazon API Gateway (HTTP API)
- **インフラ管理**: Terraform
- **状態管理**: S3バケット

## APIエンドポイント

- **パス**: `/`
- **メソッド**: ANY
- **レスポンス**: `{ "message": "hello" }`

## 技術的詳細

- Lambda関数はARM64アーキテクチャで実行されます
- コンテナイメージはECRに保存されます
- API GatewayはHTTP APIタイプを使用しています
- Terraformの状態はS3バケットに保存されます
- ローカル開発用のHTTPサーバーも含まれています
- API Gatewayシミュレーターを使用して、Lambda関数をローカルでデバッグできます

## デバッグ方法

### Lambda関数のデバッグ

Lambda関数のデバッグには、以下の方法があります：

1. **ローカルHTTPサーバー**: 基本的なHTTPリクエストをテストします
2. **API Gatewayシミュレーター**: API Gatewayからのリクエストをシミュレートし、Lambda関数の動作をデバッグします
3. **AWS CloudWatch Logs**: デプロイ後のLambda関数のログを確認します

API Gatewayシミュレーターを使用すると、Lambda関数が受け取るリクエストの詳細と、関数が返すレスポンスの詳細がログに出力されます。これにより、AWS環境にデプロイする前に問題を特定できます。

## クリーンアップ

リソースを削除するには：

```bash
cd terraform && terraform destroy
``` 