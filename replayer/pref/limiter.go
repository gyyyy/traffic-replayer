package pref

import (
	"sync"
	"time"
)

// rateLimiter 简易速率限制器
type rateLimiter struct {
	mu        sync.Mutex
	enabled   bool
	pps       int64 // 包速率限制
	bps       int64 // 字节速率限制
	tokens    chan struct{}
	lastReset time.Time
}

// refill 定期填充令牌
func (l *rateLimiter) refill() {
	if l.pps <= 0 {
		return
	}
	ticker := time.NewTicker(time.Second / time.Duration(l.pps))
	defer ticker.Stop()
	for range ticker.C {
		select {
		case l.tokens <- struct{}{}:
		default:
			// 令牌桶已满，跳过
		}
	}
}

// Wait 等待速率限制
func (l *rateLimiter) wait(packetSize int) {
	if !l.enabled {
		return
	}
	if l.pps > 0 {
		// 等待令牌
		<-l.tokens
	}
	// 简化的字节速率限制
	if l.bps > 0 {
		l.mu.Lock()
		defer l.mu.Unlock()
		// 计算需要等待的时间
		expectedTime := time.Duration(float64(packetSize) / float64(l.bps) * float64(time.Second))
		if expectedTime > 0 {
			time.Sleep(expectedTime)
		}
	}
}

// newRateLimiter 创建速率限制器
func newRateLimiter(pps, bps int64) *rateLimiter {
	rl := &rateLimiter{
		enabled:   pps > 0 || bps > 0,
		pps:       pps,
		bps:       bps,
		lastReset: time.Now(),
	}
	if rl.enabled && pps > 0 {
		// 使用令牌桶算法
		rl.tokens = make(chan struct{}, pps)
		go rl.refill()
	}
	return rl
}
