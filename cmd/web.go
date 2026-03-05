package main

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gyyyy/traffic-replayer/replayer"
	"github.com/spf13/cobra"
)

//go:embed assets/index.html
var webPageHTML []byte

var (
	webAddr        string // web 服务监听地址
	arpPacketDescs = []string{
		"ARP Request（广播，Who has DstIP? Tell SrcIP）",
		"ARP Reply（单播，DstIP is at DstMAC）",
	}
	pingPacketDescs = []string{
		"ICMP Echo Request（Ping 请求，客户端 → 目标）",
		"ICMP Echo Reply（Ping 响应，目标 → 客户端）",
	}
	httpPacketDescs = []string{
		"TCP SYN（三次握手 第 1 步，客户端 → 服务端）",
		"TCP SYN-ACK（三次握手 第 2 步，服务端 → 客户端）",
		"TCP ACK（三次握手 第 3 步，客户端 → 服务端）",
		"HTTP 请求 [PSH+ACK]（客户端 → 服务端）",
		"HTTP 请求确认 [ACK]（服务端 → 客户端）",
		"HTTP 响应 [PSH+ACK]（服务端 → 客户端）",
		"HTTP 响应确认 [ACK]（客户端 → 服务端）",
		"TCP FIN（四次挥手 第 1 步，客户端 → 服务端）",
		"TCP ACK（四次挥手 第 2 步，服务端 → 客户端）",
		"TCP FIN（四次挥手 第 3 步，服务端 → 客户端）",
		"TCP ACK（四次挥手 第 4 步，客户端 → 服务端）",
	}
)

// PacketInfo 单个数据包展示信息
type PacketInfo struct {
	Index int    `json:"index"`
	Desc  string `json:"desc"`
	Bytes int    `json:"bytes"`
}

// buildPacketInfos 将数据包列表转为展示信息，baseIdx 为本批次起始序号（0-based）
func buildPacketInfos(packets []*replayer.Packet, descs []string, baseIdx int) []PacketInfo {
	infos := make([]PacketInfo, 0, len(packets))
	for i, p := range packets {
		desc := fmt.Sprintf("数据包 #%d", baseIdx+i+1)
		if i < len(descs) {
			desc = descs[i]
		}
		infos = append(infos, PacketInfo{
			Index: baseIdx + i + 1,
			Desc:  desc,
			Bytes: len(p.Data),
		})
	}
	return infos
}

// MockRequest POST /api/mock 请求体
type MockRequest struct {
	Iface  string `json:"iface"`
	Type   string `json:"type"`
	SrcIP  string `json:"src_ip"`
	DstIP  string `json:"dst_ip"`
	SrcMAC string `json:"src_mac"`
	DstMAC string `json:"dst_mac"`
	URI    string `json:"uri"`
	Count  int    `json:"count"`
}

// MockStats 统计信息
type MockStats struct {
	PacketsSent   int64  `json:"packets_sent"`
	BytesSent     int64  `json:"bytes_sent"`
	PacketsFailed int64  `json:"packets_failed"`
	Duration      string `json:"duration"`
}

// MockResponse POST /api/mock 响应体
type MockResponse struct {
	Success bool         `json:"success"`
	Error   string       `json:"error,omitempty"`
	SrcMAC  string       `json:"src_mac,omitempty"` // 实际使用的 MAC（可能是随机生成的）
	DstMAC  string       `json:"dst_mac,omitempty"`
	Count   int          `json:"count,omitempty"`
	Packets []PacketInfo `json:"packets,omitempty"`
	Stats   *MockStats   `json:"stats,omitempty"`
}

// addStats 将 s 的统计数据累加到 total 中
func addStats(total *replayer.InjectStats, s *replayer.InjectStats) {
	if total.StartTime.IsZero() {
		total.StartTime = s.StartTime
	}
	if s.EndTime.After(total.EndTime) {
		total.EndTime = s.EndTime
	}
	total.PacketsSent += s.PacketsSent
	total.BytesSent += s.BytesSent
	total.PacketsFailed += s.PacketsFailed
}

// webRunMock 执行 mock 流量测试，返回响应（可能包含错误）
func webRunMock(req *MockRequest) *MockResponse {
	// 补齐 MAC
	srcMAC, dstMAC := req.SrcMAC, req.DstMAC
	if srcMAC == "" {
		srcMAC = replayer.RandomMAC().String()
	}
	if dstMAC == "" {
		dstMAC = replayer.RandomMAC().String()
	}
	mockType := req.Type
	if mockType == "" {
		mockType = "http"
	}
	count := req.Count
	if count <= 0 {
		count = 1
	}
	// 创建注入器
	injector, err := replayer.NewInjector(req.Iface)
	if err != nil {
		return &MockResponse{Success: false, Error: fmt.Sprintf("创建注入器失败: %v", err)}
	}
	defer injector.Close()
	var (
		templatePackets []PacketInfo // 第一轮数据包列表（展示用）
		totalStats      replayer.InjectStats
	)
	// 固定 HTTP src port，保证每轮重放同一条连接特征
	httpSrcPort := replayer.RandomPort()
	for i := 0; i < count; i++ {
		if mockType == "all" {
			// all 模式：依次执行 ARP → Ping → HTTP
			var (
				sMAC, err1 = net.ParseMAC(srcMAC)
				dMAC, err2 = net.ParseMAC(dstMAC)
			)
			if err1 != nil || err2 != nil {
				return &MockResponse{Success: false, Error: fmt.Sprintf("MAC 解析失败: %v %v", err1, err2)}
			}
			var allTemplate []PacketInfo
			// ARP
			arpPkts, arpErr := replayer.GenerateARPPackets(req.SrcIP, req.DstIP, sMAC, dMAC)
			if arpErr != nil {
				return &MockResponse{Success: false, Error: fmt.Sprintf("生成 ARP 数据包失败: %v", arpErr)}
			}
			if i == 0 {
				allTemplate = append(allTemplate, buildPacketInfos(arpPkts, arpPacketDescs, len(allTemplate))...)
			}
			addStats(&totalStats, injector.Inject(arpPkts, 1.0))
			// Ping
			pingPkts, pingErr := replayer.GenerateICMPPing(req.SrcIP, req.DstIP, sMAC, dMAC)
			if pingErr != nil {
				return &MockResponse{Success: false, Error: fmt.Sprintf("生成 ICMP 数据包失败: %v", pingErr)}
			}
			if i == 0 {
				allTemplate = append(allTemplate, buildPacketInfos(pingPkts, pingPacketDescs, len(allTemplate))...)
			}
			addStats(&totalStats, injector.Inject(pingPkts, 1.0))
			// HTTP
			gen, genErr := replayer.NewHTTPTestGenerator(req.SrcIP, req.DstIP, srcMAC, dstMAC, req.URI, httpSrcPort)
			if genErr != nil {
				return &MockResponse{Success: false, Error: fmt.Sprintf("创建 HTTP 生成器失败: %v", genErr)}
			}
			httpPkts, httpErr := gen.GeneratePackets()
			if httpErr != nil {
				return &MockResponse{Success: false, Error: fmt.Sprintf("生成 HTTP 数据包失败: %v", httpErr)}
			}
			if i == 0 {
				allTemplate = append(allTemplate, buildPacketInfos(httpPkts, httpPacketDescs, len(allTemplate))...)
				templatePackets = allTemplate
			}
			addStats(&totalStats, injector.Inject(httpPkts, 1.0))
			continue
		}
		// 单类型模式
		var (
			packets []*replayer.Packet
			descs   []string
		)
		switch mockType {
		case "arp":
			sMAC, err1 := net.ParseMAC(srcMAC)
			dMAC, err2 := net.ParseMAC(dstMAC)
			if err1 != nil || err2 != nil {
				return &MockResponse{Success: false, Error: fmt.Sprintf("MAC 解析失败: %v %v", err1, err2)}
			}
			packets, err = replayer.GenerateARPPackets(req.SrcIP, req.DstIP, sMAC, dMAC)
			descs = arpPacketDescs
		case "ping":
			sMAC, err1 := net.ParseMAC(srcMAC)
			dMAC, err2 := net.ParseMAC(dstMAC)
			if err1 != nil || err2 != nil {
				return &MockResponse{Success: false, Error: fmt.Sprintf("MAC 解析失败: %v %v", err1, err2)}
			}
			packets, err = replayer.GenerateICMPPing(req.SrcIP, req.DstIP, sMAC, dMAC)
			descs = pingPacketDescs
		case "http":
			var gen *replayer.HTTPTestGenerator
			gen, err = replayer.NewHTTPTestGenerator(req.SrcIP, req.DstIP, srcMAC, dstMAC, req.URI, httpSrcPort)
			if err != nil {
				return &MockResponse{Success: false, Error: fmt.Sprintf("创建 HTTP 生成器失败: %v", err)}
			}
			packets, err = gen.GeneratePackets()
			descs = httpPacketDescs
		default:
			return &MockResponse{Success: false, Error: fmt.Sprintf("未知测试类型: %s（支持: http, ping, arp, all）", mockType)}
		}
		if err != nil {
			return &MockResponse{Success: false, Error: fmt.Sprintf("生成数据包失败: %v", err)}
		}
		if i == 0 {
			templatePackets = buildPacketInfos(packets, descs, 0)
		}
		addStats(&totalStats, injector.Inject(packets, 1.0))
	}
	return &MockResponse{
		Success: true,
		SrcMAC:  srcMAC,
		DstMAC:  dstMAC,
		Count:   count,
		Packets: templatePackets,
		Stats: &MockStats{
			PacketsSent:   totalStats.PacketsSent,
			BytesSent:     totalStats.BytesSent,
			PacketsFailed: totalStats.PacketsFailed,
			Duration:      totalStats.EndTime.Sub(totalStats.StartTime).String(),
		},
	}
}

// handleIndex 返回 Web UI 页面
func handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	w.Write(webPageHTML) //nolint:errcheck
}

// handleMock 处理 mock 测试请求
func handleMock(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "仅支持 POST", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	var req MockRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(MockResponse{Success: false, Error: fmt.Sprintf("请求解析失败: %v", err)}) //nolint:errcheck
		return
	}
	json.NewEncoder(w).Encode(webRunMock(&req)) //nolint:errcheck
}

// LogInitResponse 是 /api/logfile/init 的响应结构
type LogInitResponse struct {
	Lines       []string `json:"lines"`
	StartOffset int64    `json:"start_offset"`
	EndOffset   int64    `json:"end_offset"`
	HasMore     bool     `json:"has_more"`
}

// LogHistoryResponse 是 /api/logfile/history 的响应结构
type LogHistoryResponse struct {
	Lines       []string `json:"lines"`
	StartOffset int64    `json:"start_offset"`
	HasMore     bool     `json:"has_more"`
}

// readLinesBeforeOffset 从文件 path 中读取 endOffset 之前最多 maxLines 行。
// 返回行列表（由旧到新）、当前视图顶部的字节偏移（用于下次分页）以及是否还有更多历史内容。
func readLinesBeforeOffset(path string, endOffset int64, maxLines int) (lines []string, startOffset int64, hasMore bool, err error) {
	var f *os.File
	f, err = os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	if endOffset < 0 {
		endOffset, err = f.Seek(0, io.SeekEnd)
		if err != nil {
			return
		}
	}
	if endOffset == 0 {
		return
	}
	const chunkSize = int64(4096)
	var (
		rawBuf []byte
		pos    = endOffset
	)
	// 向前读取，直到累积超过 maxLines+1 个换行符或到达文件开头
	for {
		toRead := chunkSize
		if pos < chunkSize {
			toRead = pos
		}
		pos -= toRead
		chunk := make([]byte, toRead)
		if _, err = f.ReadAt(chunk, pos); err != nil {
			return
		}
		rawBuf = append(chunk, rawBuf...)
		nlCount := bytes.Count(rawBuf, []byte{'\n'})
		if pos == 0 || nlCount > maxLines+1 {
			break
		}
	}
	content := string(rawBuf)
	// 去掉末尾换行（endOffset 处最后一个完整行的换行符）
	if len(content) > 0 && content[len(content)-1] == '\n' {
		content = content[:len(content)-1]
	}
	allLines := strings.Split(content, "\n")
	startOffset = pos
	// 若 pos > 0，rawBuf 的第一个"行"是不完整的碎片，丢弃它
	if pos > 0 && len(allLines) > 0 {
		fragmentBytes := int64(len(allLines[0])) + 1 // +1 for '\n'
		startOffset = pos + fragmentBytes
		allLines = allLines[1:]
		hasMore = true
	}
	// 超过 maxLines，从头部继续裁剪
	if len(allLines) > maxLines {
		excess := len(allLines) - maxLines
		excessBytes := int64(0)
		for i := 0; i < excess; i++ {
			excessBytes += int64(len(allLines[i])) + 1
		}
		startOffset += excessBytes
		allLines = allLines[excess:]
		hasMore = true
	}
	if len(allLines) == 1 && allLines[0] == "" {
		allLines = nil
	}
	lines = allLines
	return
}

// handleLogInit 返回文件末尾最后 N 行及偏移信息（GET /api/logfile/init）
func handleLogInit(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		http.Error(w, "缺少 path 参数", http.StatusBadRequest)
		return
	}
	maxLines := 300
	if n, e := strconv.Atoi(r.URL.Query().Get("tail")); e == nil && n > 0 {
		maxLines = n
	}
	// 先获取当前 EOF 偏移
	f, err := os.Open(path)
	if err != nil {
		http.Error(w, fmt.Sprintf("打开文件失败: %v", err), http.StatusInternalServerError)
		return
	}
	endOffset, err := f.Seek(0, io.SeekEnd)
	f.Close()
	if err != nil {
		http.Error(w, fmt.Sprintf("seek 失败: %v", err), http.StatusInternalServerError)
		return
	}
	lines, startOffset, hasMore, err := readLinesBeforeOffset(path, endOffset, maxLines)
	if err != nil {
		http.Error(w, fmt.Sprintf("读取文件失败: %v", err), http.StatusInternalServerError)
		return
	}
	if lines == nil {
		lines = []string{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(LogInitResponse{ //nolint:errcheck
		Lines:       lines,
		StartOffset: startOffset,
		EndOffset:   endOffset,
		HasMore:     hasMore,
	})
}

// handleLogHistory 返回指定偏移之前的历史行（GET /api/logfile/history）
func handleLogHistory(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		http.Error(w, "缺少 path 参数", http.StatusBadRequest)
		return
	}
	endOffset, err := strconv.ParseInt(r.URL.Query().Get("end_offset"), 10, 64)
	if err != nil || endOffset < 0 {
		http.Error(w, "无效的 end_offset 参数", http.StatusBadRequest)
		return
	}
	maxLines := 300
	if n, e := strconv.Atoi(r.URL.Query().Get("lines")); e == nil && n > 0 {
		maxLines = n
	}
	lines, startOffset, hasMore, err := readLinesBeforeOffset(path, endOffset, maxLines)
	if err != nil {
		http.Error(w, fmt.Sprintf("读取文件失败: %v", err), http.StatusInternalServerError)
		return
	}
	if lines == nil {
		lines = []string{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(LogHistoryResponse{ //nolint:errcheck
		Lines:       lines,
		StartOffset: startOffset,
		HasMore:     hasMore,
	})
}

// handleLogTail 是日志文件的 SSE 流式接口（GET /api/logfile/tail）
// 查询参数：path（文件路径）、offset（起始字节偏移，不填则从当前 EOF 开始）
// 每个 SSE message 携带 JSON：{"offset": N, "text": "..."}
func handleLogTail(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		http.Error(w, "缺少 path 参数", http.StatusBadRequest)
		return
	}
	// O_RDONLY 打开：OS 允许读写并发，不会阻塞或干扰 deeptrace 等写入方
	f, err := os.Open(path)
	if err != nil {
		http.Error(w, fmt.Sprintf("打开文件失败: %v", err), http.StatusInternalServerError)
		return
	}
	defer f.Close()
	var currentOffset int64
	if offsetStr := r.URL.Query().Get("offset"); offsetStr != "" {
		if off, e := strconv.ParseInt(offsetStr, 10, 64); e == nil && off >= 0 {
			currentOffset = off
			f.Seek(currentOffset, io.SeekStart) //nolint:errcheck
		} else {
			currentOffset, _ = f.Seek(0, io.SeekEnd)
		}
	} else {
		currentOffset, _ = f.Seek(0, io.SeekEnd)
	}
	// SSE 响应头
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no") // 禁用 nginx 等代理的缓冲
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "不支持流式传输", http.StatusInternalServerError)
		return
	}
	// 发送连接确认事件
	fmt.Fprintf(w, "event: connected\ndata: ok\n\n")
	flusher.Flush()
	var (
		ctx    = r.Context()
		buf    = make([]byte, 32*1024)
		ticker = time.NewTicker(300 * time.Millisecond)
	)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			n, err := f.Read(buf)
			if n > 0 {
				currentOffset += int64(n)
				payload, _ := json.Marshal(map[string]any{
					"offset": currentOffset,
					"text":   string(buf[:n]),
				})
				fmt.Fprintf(w, "data: %s\n\n", payload)
				flusher.Flush()
			}
			if err != nil && err != io.EOF {
				fmt.Fprintf(w, "event: error\ndata: read error: %v\n\n", err)
				flusher.Flush()
				return
			}
		}
	}
}

// runWebServer 启动 Web 服务
func runWebServer(cmd *cobra.Command, args []string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleIndex)
	mux.HandleFunc("/api/mock", handleMock)
	mux.HandleFunc("/api/logfile/init", handleLogInit)
	mux.HandleFunc("/api/logfile/history", handleLogHistory)
	mux.HandleFunc("/api/logfile/tail", handleLogTail)
	// 启动服务器
	log.Printf("Traffic Replayer Web Console 启动中...")
	log.Printf("访问地址: http://%s", webAddr)
	log.Printf("按 Ctrl+C 停止服务")
	if err := http.ListenAndServe(webAddr, mux); err != nil {
		log.Fatalf("启动服务失败: %v", err)
	}
}

// NewWebCommand 创建 web 子命令
func NewWebCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "web",
		Short: "Web 控制台模式 - 启动本地 Web UI 进行测试",
		Long: `Web 控制台模式：启动本地 HTTP 服务，提供 Web 界面进行 mock 测试和日志实时监控。

功能：
  - 通过表单输入参数，发送模拟流量（ARP / ICMP Ping / HTTP / All）
  - 实时监控任意文件内容（如 deeptrace 日志），使用只读方式打开，不影响写入方

示例:
  ./traffic-replayer web
  ./traffic-replayer web --addr :18080
  ./traffic-replayer web --addr 0.0.0.0:18080`,
		Run: runWebServer,
	}
	cmd.Flags().StringVar(&webAddr, "addr", ":18080", "Web 服务监听地址（默认 :18080）")
	return cmd
}
