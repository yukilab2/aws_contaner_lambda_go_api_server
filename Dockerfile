FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY app/ .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o /main

FROM public.ecr.aws/lambda/provided:al2-arm64
COPY --from=builder /main /var/runtime/bootstrap
RUN chmod 755 /var/runtime/bootstrap 
ENTRYPOINT [ "/var/runtime/bootstrap" ] 