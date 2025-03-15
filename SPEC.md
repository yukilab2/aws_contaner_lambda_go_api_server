# API server

- lambda
  - go 実行ファイルを含むコンテナ
    go API サーバ
        path: /
        response { "message": "hello" }

- プロビジョニング：terraform
  - terraformのバックエンドは S3
  - AWS_PROFILE: pcafe_yukilab_tokyo
  - region は ap-northeast-1 (tokyo)を使用
  - AWS ディフォルトタグを設定すること
  - ECR への コンテナデプロイ
  - API gatewayで接続する。
        API エンドポイントはAWSがつけるものを使用
        ログイン不要

- ローカルおよびlambdaの実行環境をarm64に指定してください。
- 使い方はREADMEに書いてください
- goプログラムはローカルでもテストすること
