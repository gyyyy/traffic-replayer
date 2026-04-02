package replayer

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"net"
	"net/url"
	"strings"
	"time"

	"github.com/google/gopacket"
	"github.com/google/gopacket/layers"
)

// randomInt 生成随机整数
func randomInt(max int) int {
	n, _ := rand.Int(rand.Reader, big.NewInt(int64(max)))
	return int(n.Int64())
}

// randomString 生成随机字符串
func randomString(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[randomInt(len(charset))]
	}
	return string(b)
}

// RandomMAC 生成随机 MAC 地址（本地管理单播地址）
func RandomMAC() net.HardwareAddr {
	mac := make([]byte, 6)
	rand.Read(mac)
	mac[0] = (mac[0] | 0x02) & 0xfe
	return mac
}

// RandomPort 生成一个随机的临时端口（49152–65535）
func RandomPort() uint16 {
	return uint16(49152 + randomInt(16384))
}

// createARPPacket 创建 ARP 数据包
func createARPPacket(srcMAC, dstMAC net.HardwareAddr, srcIP, dstIP net.IP, operation uint16) ([]byte, error) {
	buf := gopacket.NewSerializeBuffer()
	if err := gopacket.SerializeLayers(buf, gopacket.SerializeOptions{
		ComputeChecksums: true,
		FixLengths:       true,
	}, &layers.Ethernet{
		SrcMAC:       srcMAC,
		DstMAC:       dstMAC,
		EthernetType: layers.EthernetTypeARP,
	}, &layers.ARP{
		AddrType:          layers.LinkTypeEthernet,
		Protocol:          layers.EthernetTypeIPv4,
		HwAddressSize:     6,
		ProtAddressSize:   4,
		Operation:         operation,
		SourceHwAddress:   srcMAC,
		SourceProtAddress: srcIP,
		DstHwAddress:      dstMAC,
		DstProtAddress:    dstIP,
	}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// GenerateARPPackets 生成 ARP 请求和响应
func GenerateARPPackets(srcIP, dstIP string, srcMAC, dstMAC net.HardwareAddr) ([]*Packet, error) {
	var (
		packets  []*Packet
		baseTime = time.Now()
		sip      = net.ParseIP(srcIP).To4()
		dip      = net.ParseIP(dstIP).To4()
	)
	// ARP Request (broadcast)
	reqData, err := createARPPacket(srcMAC, net.HardwareAddr{0xff, 0xff, 0xff, 0xff, 0xff, 0xff}, sip, dip, layers.ARPRequest)
	if err != nil {
		return nil, err
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime,
		Data:      reqData,
	})
	// ARP Reply
	replyData, err := createARPPacket(dstMAC, srcMAC, dip, sip, layers.ARPReply)
	if err != nil {
		return nil, err
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(5 * time.Millisecond),
		Data:      replyData,
	})
	return packets, nil
}

// createICMPPacket 创建 ICMP 数据包
func createICMPPacket(srcMAC, dstMAC net.HardwareAddr, srcIP, dstIP net.IP, isRequest bool) ([]byte, error) {
	icmpType := layers.ICMPv4TypeEchoReply
	if isRequest {
		icmpType = layers.ICMPv4TypeEchoRequest
	}
	buf := gopacket.NewSerializeBuffer()
	if err := gopacket.SerializeLayers(buf, gopacket.SerializeOptions{
		ComputeChecksums: true,
		FixLengths:       true,
	}, &layers.Ethernet{
		SrcMAC:       srcMAC,
		DstMAC:       dstMAC,
		EthernetType: layers.EthernetTypeIPv4,
	}, &layers.IPv4{
		Version:  4,
		TTL:      64,
		Protocol: layers.IPProtocolICMPv4,
		SrcIP:    srcIP,
		DstIP:    dstIP,
	}, &layers.ICMPv4{
		TypeCode: layers.CreateICMPv4TypeCode(uint8(icmpType), 0),
		Id:       uint16(randomInt(65536)),
		Seq:      1,
	}, gopacket.Payload([]byte("ICMP Ping Test Data"))); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// GenerateICMPPing 生成 ICMP Ping 请求和响应
func GenerateICMPPing(srcIP, dstIP string, srcMAC, dstMAC net.HardwareAddr) ([]*Packet, error) {
	var (
		packets  []*Packet
		baseTime = time.Now()
		sip      = net.ParseIP(srcIP)
		dip      = net.ParseIP(dstIP)
	)
	// ICMP Echo Request
	reqData, err := createICMPPacket(srcMAC, dstMAC, sip, dip, true)
	if err != nil {
		return nil, err
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime,
		Data:      reqData,
	})
	// ICMP Echo Reply
	replyData, err := createICMPPacket(dstMAC, srcMAC, dip, sip, false)
	if err != nil {
		return nil, err
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(10 * time.Millisecond),
		Data:      replyData,
	})
	return packets, nil
}

// HTTPTestGenerator HTTP 测试流量生成器
type HTTPTestGenerator struct {
	srcMAC    net.HardwareAddr
	dstMAC    net.HardwareAddr
	srcIP     net.IP
	dstIP     net.IP
	srcPort   uint16
	dstPort   uint16
	customURI string // 自定义 URI，支持*占位符
}

// createTCPPacket 创建 TCP 数据包
func (g *HTTPTestGenerator) createTCPPacket(_ time.Time, flags uint8, seq, ack uint32, payload []byte) ([]byte, error) {
	var (
		eth = &layers.Ethernet{
			SrcMAC:       g.srcMAC,
			DstMAC:       g.dstMAC,
			EthernetType: layers.EthernetTypeIPv4,
		}
		ip  *layers.IPv4
		tcp *layers.TCP
	)
	// 判断是客户端发送还是服务器发送
	// TCP 标志位: SYN=0x02, ACK=0x10, PSH=0x08, FIN=0x01
	if (flags&0x02 != 0 && flags&0x10 == 0) || (flags&0x08 != 0) || (flags&0x01 != 0 && seq < ack) {
		// 客户端到服务器
		ip = &layers.IPv4{
			Version:  4,
			TTL:      64,
			Protocol: layers.IPProtocolTCP,
			SrcIP:    g.srcIP,
			DstIP:    g.dstIP,
		}
		tcp = &layers.TCP{
			SrcPort: layers.TCPPort(g.srcPort),
			DstPort: layers.TCPPort(g.dstPort),
			Seq:     seq,
			Ack:     ack,
			Window:  65535,
		}
	} else {
		// 服务器到客户端
		ip = &layers.IPv4{
			Version:  4,
			TTL:      64,
			Protocol: layers.IPProtocolTCP,
			SrcIP:    g.dstIP,
			DstIP:    g.srcIP,
		}
		tcp = &layers.TCP{
			SrcPort: layers.TCPPort(g.dstPort),
			DstPort: layers.TCPPort(g.srcPort),
			Seq:     seq,
			Ack:     ack,
			Window:  65535,
		}
	}
	// 设置 TCP 标志
	if flags&0x02 != 0 {
		tcp.SYN = true
	}
	if flags&0x10 != 0 {
		tcp.ACK = true
	}
	if flags&0x08 != 0 {
		tcp.PSH = true
	}
	if flags&0x01 != 0 {
		tcp.FIN = true
	}
	// 设置校验和
	tcp.SetNetworkLayerForChecksum(ip)
	// 序列化数据包
	var (
		buf  = gopacket.NewSerializeBuffer()
		opts = gopacket.SerializeOptions{
			ComputeChecksums: true,
			FixLengths:       true,
		}
	)
	if len(payload) > 0 {
		if err := gopacket.SerializeLayers(buf, opts, eth, ip, tcp, gopacket.Payload(payload)); err != nil {
			return nil, err
		}
	} else {
		if err := gopacket.SerializeLayers(buf, opts, eth, ip, tcp); err != nil {
			return nil, err
		}
	}
	return buf.Bytes(), nil
}

// processURIWithRandomization 处理 URI 中的*占位符，将其替换为随机值
func (g *HTTPTestGenerator) processURIWithRandomization(uri string) string {
	var result strings.Builder
	for _, r := range uri {
		if r == '*' {
			// 生成随机值（数字或字符串）
			if randomInt(2) == 0 {
				// 生成随机数字
				fmt.Fprintf(&result, "%d", randomInt(100000))
			} else {
				// 生成随机字符串
				result.WriteString(randomString(8))
			}
		} else {
			result.WriteRune(r)
		}
	}
	return result.String()
}

// encodeURI 对 URI 进行百分号编码，确保非 ASCII 字符（如中文）被正确编码
func encodeURI(rawURI string) string {
	u, err := url.Parse(rawURI)
	if err != nil {
		return rawURI
	}
	if u.RawQuery != "" {
		u.RawQuery = u.Query().Encode()
	}
	return u.RequestURI()
}

// generateHTTPRequest 生成 HTTP 请求（支持自定义 URI）
func (g *HTTPTestGenerator) generateHTTPRequest() string {
	var path string
	if g.customURI != "" {
		// 使用自定义 URI，并处理*占位符，然后对非 ASCII 字符进行 URL 编码
		path = encodeURI(g.processURIWithRandomization(g.customURI))
	} else {
		// 使用默认的随机路径
		paths := []string{
			"/api/users",
			"/api/products",
			"/api/orders",
			"/api/data",
			"/api/search",
			"/api/status",
			"/health",
			"/metrics",
			"/v1/items",
			"/v2/resources",
		}
		// 添加随机查询参数
		path = fmt.Sprintf("%s?id=%d&token=%s", paths[randomInt(len(paths))], randomInt(10000), randomString(16))
	}
	return fmt.Sprintf("GET %s HTTP/1.1\r\n"+
		"Host: example.com\r\n"+
		"User-Agent: Traffic-Replayer-Test/1.0\r\n"+
		"Accept: application/json\r\n"+
		"Connection: keep-alive\r\n"+
		"\r\n", path)
}

// generateHTTPResponse 生成 HTTP 响应
func (g *HTTPTestGenerator) generateHTTPResponse() string {
	responses := []string{
		`{"status":"success","data":{"id":123,"name":"test"}}`,
		`{"status":"ok","message":"Request processed"}`,
		`{"result":"completed","timestamp":1234567890}`,
		`{"data":[{"id":1,"value":"abc"},{"id":2,"value":"def"}]}`,
		`{"success":true,"code":200,"info":"Operation successful"}`,
	}
	// 随机响应体
	body := responses[randomInt(len(responses))]
	return fmt.Sprintf("HTTP/1.1 200 OK\r\n"+
		"Content-Type: application/json\r\n"+
		"Content-Length: %d\r\n"+
		"Connection: keep-alive\r\n"+
		"Server: Test-Server/1.0\r\n"+
		"\r\n"+
		"%s", len(body), body)
}

// GeneratePackets 生成完整的 HTTP 会话数据包
func (g *HTTPTestGenerator) GeneratePackets() ([]*Packet, error) {
	var (
		packets  []*Packet
		baseTime = time.Now()
	)
	// 1. TCP 三次握手
	// SYN (TCP 标志位: 0x02)
	syn, err := g.createTCPPacket(baseTime, 0x02, 1000, 0, nil)
	if err != nil {
		return nil, fmt.Errorf("创建 SYN 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime,
		Data:      syn,
	})
	// SYN-ACK (TCP 标志位: 0x12 = SYN|ACK)
	synAck, err := g.createTCPPacket(baseTime.Add(10*time.Millisecond), 0x12, 2000, 1001, nil)
	if err != nil {
		return nil, fmt.Errorf("创建 SYN-ACK 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(10 * time.Millisecond),
		Data:      synAck,
	})
	// ACK (TCP 标志位: 0x10)
	ack, err := g.createTCPPacket(baseTime.Add(20*time.Millisecond), 0x10, 1001, 2001, nil)
	if err != nil {
		return nil, fmt.Errorf("创建 ACK 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(20 * time.Millisecond),
		Data:      ack,
	})
	// 2. HTTP 请求
	httpRequest := g.generateHTTPRequest()
	// PSH|ACK (TCP 标志位: 0x18)
	reqPacket, err := g.createTCPPacket(baseTime.Add(30*time.Millisecond), 0x18, 1001, 2001, []byte(httpRequest))
	if err != nil {
		return nil, fmt.Errorf("创建 HTTP 请求包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(30 * time.Millisecond),
		Data:      reqPacket,
	})
	// ACK for HTTP request
	reqAck, err := g.createTCPPacket(baseTime.Add(40*time.Millisecond), 0x10, 2001, uint32(1001+len(httpRequest)), nil)
	if err != nil {
		return nil, fmt.Errorf("创建 HTTP 请求 ACK 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(40 * time.Millisecond),
		Data:      reqAck,
	})
	// 3. HTTP 响应
	httpResponse := g.generateHTTPResponse()
	// PSH|ACK (TCP 标志位: 0x18)
	respPacket, err := g.createTCPPacket(baseTime.Add(50*time.Millisecond), 0x18, 2001, uint32(1001+len(httpRequest)), []byte(httpResponse))
	if err != nil {
		return nil, fmt.Errorf("创建 HTTP 响应包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(50 * time.Millisecond),
		Data:      respPacket,
	})
	// ACK for HTTP response
	respAck, err := g.createTCPPacket(baseTime.Add(60*time.Millisecond), 0x10, uint32(1001+len(httpRequest)), uint32(2001+len(httpResponse)), nil)
	if err != nil {
		return nil, fmt.Errorf("创建 HTTP 响应 ACK 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(60 * time.Millisecond),
		Data:      respAck,
	})
	// 4. TCP 四次挥手
	// FIN from client (FIN|ACK: 0x11)
	fin1, err := g.createTCPPacket(baseTime.Add(70*time.Millisecond), 0x11, uint32(1001+len(httpRequest)), uint32(2001+len(httpResponse)), nil)
	if err != nil {
		return nil, fmt.Errorf("创建 FIN 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(70 * time.Millisecond),
		Data:      fin1,
	})
	// ACK from server
	fin1Ack, err := g.createTCPPacket(baseTime.Add(80*time.Millisecond), 0x10, uint32(2001+len(httpResponse)), uint32(1002+len(httpRequest)), nil)
	if err != nil {
		return nil, fmt.Errorf("创建 FIN ACK 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(80 * time.Millisecond),
		Data:      fin1Ack,
	})
	// FIN from server (FIN|ACK: 0x11)
	fin2, err := g.createTCPPacket(baseTime.Add(90*time.Millisecond), 0x11, uint32(2001+len(httpResponse)), uint32(1002+len(httpRequest)), nil)
	if err != nil {
		return nil, fmt.Errorf("创建服务器 FIN 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(90 * time.Millisecond),
		Data:      fin2,
	})
	// Final ACK from client
	finalAck, err := g.createTCPPacket(baseTime.Add(100*time.Millisecond), 0x10, uint32(1002+len(httpRequest)), uint32(2002+len(httpResponse)), nil)
	if err != nil {
		return nil, fmt.Errorf("创建最终 ACK 包失败: %v", err)
	}
	packets = append(packets, &Packet{
		Timestamp: baseTime.Add(100 * time.Millisecond),
		Data:      finalAck,
	})
	return packets, nil
}

// NewHTTPTestGenerator 创建 HTTP 测试流量生成器
// srcPort 指定源端口，传 0 时自动随机生成
func NewHTTPTestGenerator(srcIP, dstIP string, srcMAC, dstMAC string, customURI string, srcPort uint16) (*HTTPTestGenerator, error) {
	g := &HTTPTestGenerator{
		srcPort:   srcPort,
		dstPort:   80,
		customURI: customURI,
	}
	if g.srcPort == 0 {
		g.srcPort = RandomPort()
	}
	// 解析 IP 地址
	g.srcIP = net.ParseIP(srcIP)
	if g.srcIP == nil {
		return nil, fmt.Errorf("无效的源 IP 地址: %s", srcIP)
	}
	g.dstIP = net.ParseIP(dstIP)
	if g.dstIP == nil {
		return nil, fmt.Errorf("无效的目标 IP 地址: %s", dstIP)
	}
	// 解析 MAC 地址
	if srcMAC != "" {
		mac, err := net.ParseMAC(srcMAC)
		if err != nil {
			return nil, fmt.Errorf("无效的源 MAC 地址: %s", srcMAC)
		}
		g.srcMAC = mac
	} else {
		// 生成随机 MAC 地址
		g.srcMAC = RandomMAC()
	}
	if dstMAC != "" {
		mac, err := net.ParseMAC(dstMAC)
		if err != nil {
			return nil, fmt.Errorf("无效的目标 MAC 地址: %s", dstMAC)
		}
		g.dstMAC = mac
	} else {
		// 生成随机 MAC 地址
		g.dstMAC = RandomMAC()
	}
	return g, nil
}
