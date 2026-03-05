# 本地测试 Docker 镜像
FROM golang:1.24 AS builder

# 安装编译依赖
RUN apt-get update -qq && apt-get install -y -qq \
    gcc \
    libpcap-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /traffic-replayer ./cmd

# 运行时环境
FROM debian:bookworm-slim

# 安装运行时依赖
RUN apt-get update -qq && apt-get install -y -qq \
    libpcap0.8 \
    tcpdump \
    iproute2 \
    bash \
    && rm -rf /var/lib/apt/lists/*

# 复制可执行文件和测试数据
COPY --from=builder /traffic-replayer /usr/local/bin/traffic-replayer
COPY docker/local-test/data /test/data
COPY docker/local-test/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 创建输出目录
RUN mkdir -p /test/output /test/logs

WORKDIR /test

ENTRYPOINT ["/entrypoint.sh"]
CMD ["test"]
