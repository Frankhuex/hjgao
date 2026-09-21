extends GameSession

# 保留生产场景和网络逻辑，仅阻止测试客户端自动开无头服务器。
var suppress_auto_host: bool = true

func start_server(port: int, headless: bool) -> void:
	if not suppress_auto_host:
		super.start_server(port, headless)
