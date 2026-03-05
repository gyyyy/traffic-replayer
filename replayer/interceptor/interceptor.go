package interceptor

// Interceptor 数据包拦截器
type Interceptor func(PacketModifier) PacketModifier

// Chain 创建链式拦截器
func Chain(interceptors ...Interceptor) Interceptor {
	return func(packet PacketModifier) PacketModifier {
		for _, interceptor := range interceptors {
			if interceptor == nil {
				continue
			}
			packet = interceptor(packet)
		}
		return packet
	}
}
