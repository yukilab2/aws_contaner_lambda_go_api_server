package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

type Response struct {
	Message string `json:"message"`
}

// リクエストの詳細をログに出力する
func logRequest(request events.APIGatewayProxyRequest) {
	fmt.Println("=== API Gateway Request ===")
	fmt.Printf("Path: %s\n", request.Path)
	fmt.Printf("HTTPMethod: %s\n", request.HTTPMethod)
	fmt.Printf("Headers: %v\n", request.Headers)
	fmt.Printf("QueryStringParameters: %v\n", request.QueryStringParameters)
	fmt.Printf("PathParameters: %v\n", request.PathParameters)
	fmt.Printf("Body: %s\n", request.Body)
	fmt.Println("=========================")
}

func handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// リクエストの詳細をログに出力
	logRequest(request)

	resp := Response{Message: "hello"}
	body, _ := json.Marshal(resp)

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil
}

func localHandler(w http.ResponseWriter, r *http.Request) {
	// HTTPリクエストの詳細をログに出力
	fmt.Println("=== HTTP Request ===")
	fmt.Printf("Method: %s\n", r.Method)
	fmt.Printf("URL: %s\n", r.URL.String())
	fmt.Printf("Headers: %v\n", r.Header)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		fmt.Printf("Error reading body: %v\n", err)
	} else {
		fmt.Printf("Body: %s\n", string(body))
	}
	fmt.Println("===================")

	resp := Response{Message: "hello"}
	respBody, _ := json.Marshal(resp)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(respBody)
}

// API Gatewayのリクエストをシミュレートするハンドラー
func apiGatewaySimulatorHandler(w http.ResponseWriter, r *http.Request) {
	// API Gatewayリクエストを構築
	headers := make(map[string]string)
	for name, values := range r.Header {
		if len(values) > 0 {
			headers[name] = values[0]
		}
	}

	queryParams := make(map[string]string)
	for name, values := range r.URL.Query() {
		if len(values) > 0 {
			queryParams[name] = values[0]
		}
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read body", http.StatusInternalServerError)
		return
	}

	// API Gatewayリクエストを作成
	apiGatewayRequest := events.APIGatewayProxyRequest{
		Path:                  r.URL.Path,
		HTTPMethod:            r.Method,
		Headers:               headers,
		QueryStringParameters: queryParams,
		Body:                  string(body),
		IsBase64Encoded:       false,
	}

	// リクエストをログに出力
	requestJSON, _ := json.MarshalIndent(apiGatewayRequest, "", "  ")
	fmt.Println("=== API Gateway Simulator Request ===")
	fmt.Println(string(requestJSON))
	fmt.Println("====================================")

	// Lambda関数を直接呼び出し
	response, err := handler(context.Background(), apiGatewayRequest)
	if err != nil {
		http.Error(w, fmt.Sprintf("Lambda handler error: %v", err), http.StatusInternalServerError)
		return
	}

	// レスポンスをログに出力
	responseJSON, _ := json.MarshalIndent(response, "", "  ")
	fmt.Println("=== API Gateway Simulator Response ===")
	fmt.Println(string(responseJSON))
	fmt.Println("=====================================")

	// レスポンスヘッダーを設定
	for key, value := range response.Headers {
		w.Header().Set(key, value)
	}

	// ステータスコードを設定
	w.WriteHeader(response.StatusCode)

	// レスポンスボディを書き込み
	w.Write([]byte(response.Body))
}

func main() {
	local := flag.Bool("local", false, "ローカルサーバーとして実行")
	simulator := flag.Bool("simulator", false, "API Gatewayシミュレーターとして実行")
	port := flag.String("port", "8080", "ローカルサーバーのポート")
	flag.Parse()

	// ログの設定
	log.SetOutput(os.Stdout)

	if *local {
		http.HandleFunc("/", localHandler)
		fmt.Printf("ローカルサーバーを起動しています。http://localhost:%s/\n", *port)
		log.Fatal(http.ListenAndServe(":"+*port, nil))
	} else if *simulator {
		http.HandleFunc("/", apiGatewaySimulatorHandler)
		fmt.Printf("API Gatewayシミュレーターを起動しています。http://localhost:%s/\n", *port)
		log.Fatal(http.ListenAndServe(":"+*port, nil))
	} else {
		lambda.Start(handler)
	}
}
