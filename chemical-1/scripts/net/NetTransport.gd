# ============================================================
# NetTransport.gd - 传输层抽象接口（P11-B 地基）
# 上层（NetSession）只依赖本接口，具体实现：
#   LoopbackTransport : 进程内回环（测试 / 单机自测）
#   ENetTransport     : 局域网 / Tailscale / 隧道（P11-C1）
#   WebRTCTransport   : 跨 NAT P2P（P11-C2）
# 换传输方式时 NetSession / GameManager / GameUI 零改动。
# 约定：所有实现都通过 poll() 派发信号（不要在 send 里同步触发）。
# ============================================================
extends RefCounted

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(peer_id: int, data: PackedByteArray)

enum Mode { NONE, HOST, CLIENT }

var mode: int = Mode.NONE
var local_id: int = 1


# 返回 0 = 成功，负值 = 失败
func host(_port: int, _max_players: int = 4) -> int:
	return -1


# 返回 0 = 成功（真正连上以 peer_connected 信号为准）
func join(_address: String, _port: int) -> int:
	return -1


func close() -> void:
	pass


# 每个渲染帧调用一次：把底层网络事件派发成信号
func poll() -> void:
	pass


func send_to(_peer_id: int, _data: PackedByteArray) -> int:
	return -1


func broadcast(_data: PackedByteArray) -> int:
	return -1


func get_peers() -> Array:
	return []


func is_connected_to(_peer_id: int) -> bool:
	return false


func get_transport_name() -> String:
	return "none"
