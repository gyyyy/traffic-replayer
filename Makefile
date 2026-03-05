# 流量回放工具 Makefile
# 支持交叉编译到不同平台

# 项目信息
PROJECT_NAME := traffic-replayer
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "v1.0")
BUILD_TIME := $(shell TZ='Asia/Shanghai' date '+%Y-%m-%d_%H:%M:%S')

# 编译参数
LDFLAGS := -ldflags "-X main.version=$(VERSION) -X main.buildTime=$(BUILD_TIME)"
GOFLAGS := -trimpath

# 目录
BIN_DIR := bin
CMD_DIR := cmd

# 默认目标
.PHONY: all
all: build

# 编译当前平台版本
.PHONY: build
build:
	@echo "正在构建 $(PROJECT_NAME) $(VERSION)..."
	@mkdir -p $(BIN_DIR)
	go build $(GOFLAGS) $(LDFLAGS) -o $(BIN_DIR)/$(PROJECT_NAME) ./$(CMD_DIR)
	@echo "✓ 构建完成: $(BIN_DIR)/$(PROJECT_NAME)"

# 交叉编译到 Linux AMD64
.PHONY: build-linux
build-linux:
	@echo "正在交叉编译到 Linux AMD64..."
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build $(GOFLAGS) $(LDFLAGS) -o $(BIN_DIR)/$(PROJECT_NAME)-linux-amd64 ./$(CMD_DIR)
	@echo "✓ 构建完成: $(BIN_DIR)/$(PROJECT_NAME)-linux-amd64"

# 使用 Docker 构建 Linux AMD64
.PHONY: build-linux-docker
build-linux-docker:
	@echo "正在使用 Docker 构建 Linux AMD64 版本..."
	@mkdir -p $(BIN_DIR)
	docker run --rm \
		-v "$(PWD):/src" \
		-w /src \
		-e VERSION="$(VERSION)" \
		-e BUILD_TIME="$(BUILD_TIME)" \
		golang:1.24 \
		sh -c 'apt-get update -qq && apt-get install -y -qq libpcap-dev && go build $(GOFLAGS) -ldflags "-X main.version=$$VERSION -X main.buildTime=$$BUILD_TIME" -o $(BIN_DIR)/$(PROJECT_NAME)-linux-amd64 ./$(CMD_DIR)'
	@echo "✓ 构建完成: $(BIN_DIR)/$(PROJECT_NAME)-linux-amd64"

# 交叉编译到 Linux ARM64
.PHONY: build-linux-arm64
build-linux-arm64:
	@echo "正在交叉编译到 Linux ARM64..."
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=1 GOOS=linux GOARCH=arm64 CC=aarch64-linux-gnu-gcc go build $(GOFLAGS) $(LDFLAGS) -o $(BIN_DIR)/$(PROJECT_NAME)-linux-arm64 ./$(CMD_DIR)
	@echo "✓ 构建完成: $(BIN_DIR)/$(PROJECT_NAME)-linux-arm64"

# 使用 Docker 构建 Linux ARM64
.PHONY: build-linux-arm64-docker
build-linux-arm64-docker:
	@echo "正在使用 Docker 构建 Linux ARM64 版本..."
	@mkdir -p $(BIN_DIR)
	docker run --rm --platform linux/arm64 \
		-v "$(PWD):/src" \
		-w /src \
		-e VERSION="$(VERSION)" \
		-e BUILD_TIME="$(BUILD_TIME)" \
		golang:1.24 \
		sh -c 'apt-get update -qq && apt-get install -y -qq libpcap-dev && go build $(GOFLAGS) -ldflags "-X main.version=$$VERSION -X main.buildTime=$$BUILD_TIME" -o $(BIN_DIR)/$(PROJECT_NAME)-linux-arm64 ./$(CMD_DIR)'
	@echo "✓ 构建完成: $(BIN_DIR)/$(PROJECT_NAME)-linux-arm64"

# 交叉编译到 macOS AMD64
.PHONY: build-darwin
build-darwin:
	@echo "正在交叉编译到 macOS AMD64..."
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build $(GOFLAGS) $(LDFLAGS) -o $(BIN_DIR)/$(PROJECT_NAME)-darwin-amd64 ./$(CMD_DIR)
	@echo "✓ 构建完成: $(BIN_DIR)/$(PROJECT_NAME)-darwin-amd64"

# 交叉编译到 macOS ARM64 (Apple Silicon)
.PHONY: build-darwin-arm64
build-darwin-arm64:
	@echo "正在交叉编译到 macOS ARM64..."
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build $(GOFLAGS) $(LDFLAGS) -o $(BIN_DIR)/$(PROJECT_NAME)-darwin-arm64 ./$(CMD_DIR)
	@echo "✓ 构建完成: $(BIN_DIR)/$(PROJECT_NAME)-darwin-arm64"

# 交叉编译到 Windows AMD64
.PHONY: build-windows
build-windows:
	@echo "正在交叉编译到 Windows AMD64..."
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build $(GOFLAGS) $(LDFLAGS) -o $(BIN_DIR)/$(PROJECT_NAME)-windows-amd64.exe ./$(CMD_DIR)
	@echo "✓ 构建完成: $(BIN_DIR)/$(PROJECT_NAME)-windows-amd64.exe"

# 编译所有平台版本
.PHONY: build-all
build-all: build-linux build-linux-arm64 build-darwin build-darwin-arm64 build-windows
	@echo "✓ 所有平台构建完成"

# 运行测试
.PHONY: test
test:
	@echo "正在运行测试..."
	go test -v ./...

# 运行测试并生成覆盖率报告
.PHONY: test-coverage
test-coverage:
	@echo "正在运行测试并生成覆盖率报告..."
	go test -v -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "✓ 覆盖率报告已生成: coverage.html"

# 格式化代码
.PHONY: fmt
fmt:
	@echo "正在格式化代码..."
	go fmt ./...
	@echo "✓ 代码格式化完成"

# 代码检查
.PHONY: lint
lint:
	@echo "正在进行代码检查..."
	@which golangci-lint > /dev/null || (echo "请先安装 golangci-lint: https://golangci-lint.run/usage/install/" && exit 1)
	golangci-lint run ./...
	@echo "✓ 代码检查完成"

# 下载依赖
.PHONY: deps
deps:
	@echo "正在下载依赖..."
	go mod download
	go mod verify
	@echo "✓ 依赖下载完成"

# 更新依赖
.PHONY: deps-update
deps-update:
	@echo "正在更新依赖..."
	go get -u ./...
	go mod tidy
	@echo "✓ 依赖更新完成"

# 清理构建产物
.PHONY: clean
clean:
	@echo "正在清理构建产物..."
	rm -rf $(BIN_DIR)
	rm -f coverage.out coverage.html
	@echo "✓ 清理完成"

# Docker 相关
.PHONY: docker-build
docker-build:
	@echo "正在构建 Docker 镜像..."
	cd docker/local-test && docker-compose build
	@echo "✓ Docker 镜像构建完成"

.PHONY: docker-test
docker-test:
	@echo "正在运行 Docker 测试..."
	./scripts/local-test.sh

# 生成测试数据
.PHONY: generate-testdata
generate-testdata:
	@echo "正在生成测试 PCAP 文件..."
	@which python3 > /dev/null || (echo "请先安装 Python 3" && exit 1)
	@python3 -c "import scapy" 2>/dev/null || (echo "请先安装 scapy: pip3 install scapy" && exit 1)
	python3 scripts/generate_test_pcaps.py
	@echo "✓ 测试数据生成完成"

# 安装到系统
.PHONY: install
install: build
	@echo "正在安装到系统..."
	sudo cp $(BIN_DIR)/$(PROJECT_NAME) /usr/local/bin/
	sudo setcap cap_net_raw,cap_net_admin=eip /usr/local/bin/$(PROJECT_NAME) 2>/dev/null || true
	@echo "✓ 安装完成: /usr/local/bin/$(PROJECT_NAME)"

# 卸载
.PHONY: uninstall
uninstall:
	@echo "正在卸载..."
	sudo rm -f /usr/local/bin/$(PROJECT_NAME)
	@echo "✓ ���载完成"

# 显示版本信息
.PHONY: version
version:    - 构建当前平台版本 (默认)"
	@echo "  build-linux              - 交叉编译到 Linux AMD64 (需要工具链)"
	@echo "  build-linux-docker       - 使用 Docker 构建 Linux AMD64 (推荐)"
	@echo "  build-linux-arm64        - 交叉编译到 Linux ARM64 (需要工具链)"
	@echo "  build-linux-arm64-docker - 使用 Docker 构建 Linux ARM64 (推荐)"
	@echo "  build-darwin             - 交叉编译到 macOS AMD64"
	@echo "  build-darwin-arm64       - 交叉编译到 macOS ARM64"
	@echo "  build-windows            - 交叉编译到 Windows AMD64"
	@echo "  build-all    
	@echo "流量回放工具 - Makefile 帮助"
	@echo ""
	@echo "使用方法: make [目标]"
	@echo ""
	@echo "构建目标:"
	@echo "  build              - 构建当前平台版本 (默认)"
	@echo "  build-linux        - 交叉编译到 Linux AMD64"
	@echo "  build-linux-arm64  - 交叉编译到 Linux ARM64"
	@echo "  build-darwin       - 交叉编译到 macOS AMD64"
	@echo "  build-darwin-arm64 - 交叉编译到 macOS ARM64"
	@echo "  build-windows      - 交叉编译到 Windows AMD64"
	@echo "  build-all          - 编译所有平台版本"
	@echo ""
	@echo "测试目标:"
	@echo "  test               - 运行单元测试"
	@echo "  test-coverage      - 运行测试并生成覆盖率报告"
	@echo "  docker-test        - 运行 Docker 集成测试"
	@echo ""
	@echo "开发目标:"
	@echo "  fmt                - 格式化代码"
	@echo "  lint               - 运行代码检查"
	@echo "  deps               - 下载依赖"
	@echo "  deps-update        - 更新依赖"
	@echo "  generate-testdata  - 生成测试 PCAP 文件"
	@echo ""
	@echo "Docker 目标:"
	@echo "  docker-build       - 构建 Docker 镜像"
	@echo "  docker-test        - 运行 Docker 测试"
	@echo ""
	@echo "安装目标:"
	@echo "  install            - 安装到系统 (/usr/local/bin)"
	@echo "  uninstall          - 从系统卸载"
	@echo ""
	@echo "其他目标:"
	@echo "  clean              - 清理构建产物"
	@echo "  version            - 显示版本信息"
	@echo "  help               - 显示此帮助信息"
	@echo ""
