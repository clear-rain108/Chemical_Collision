# ============================================================
# LoopbackTransport.gd - 进程内回环传输（P11-B 地基）
# 用途：无网络环境下测试协议往返、主机-客人数一致性、断线流程。
# 用法：
#   var a = LoopbackTransportScript.new()
#   var b = LoopbackTransportScript.new()
#   a.link(b)
#   a.host(0)          # a 成为主机（local_id = 1）
#   b.join("", 0)      # b 成为客人（local_id = 2）
#   a.send_to(2, bytes) / b.poll() → packet_received
# ============================================================
extends "res://scripts/net/NetTransport.gd"

var _link = null                    # 对端实例
var _remote_id: int = 0
var _inbox: Array = []              # [[from_id, PackedByteArray], ...]
var _pending: Array = []            # [["connected"/"packet"/"disconnected", id, data], ...]
var _closed: bool = false


func link(other) -> void:
	_link = other
	if other != null and other._link != self:
		other.link(self)


func host(_port: int, _max_players: int = 4) -> int:
	if _link == null:
		return -1
	mode = Mode.HOST
	local_id = 1
	_remote_id = 2
	_closed = false
	_link._remote_id = 1
	_link._closed = false
	_pending.append(["connected", _remote_id])
	_link._pending.append(["connected", 1])
	return 0


func join(_address: String, _port: int) -> int:
	# 对端已 host → 连接关系已建立（id 由 host 分配好），这里只做状态确认
	if _link == null or _link.mode != Mode.HOST:
		return -1
	mode = Mode.CLIENT
	local_id = 2
	return 0


func close() -> void:
	if _closed:
		return
	_closed = true
	if _link != null and not _link._closed:
		_link._pending.append(["disconnected", local_id])
		_link._link = null      # 断开互相引用，避免 RefCounted 循环泄漏
	_link = null
	mode = Mode.NONE


func poll() -> void:
	for item in _inbox:
		_pending.append(["packet", int(item[0]), item[1]])
	_inbox.clear()
	while not _pending.is_empty():
		var e = _pending.pop_front()
		match String(e[0]):
			"connected":
				peer_connected.emit(int(e[1]))
			"packet":
				packet_received.emit(int(e[1]), e[2])
			"disconnected":
				peer_disconnected.emit(int(e[1]))


func send_to(peer_id: int, data: PackedByteArray) -> int:
	if _closed or _link == null or peer_id != _remote_id:
		return -1
	_link._inbox.append([local_id, data])
	return 0


func broadcast(data: PackedByteArray) -> int:
	return send_to(_remote_id, data)


func get_peers() -> Array:
	if _closed or _remote_id == 0:
		return []
	return [_remote_id]


func is_connected_to(peer_id: int) -> bool:
	if _closed or _link == null or peer_id != _remote_id:
		return false
	return not _link._closed


func get_transport_name() -> String:
	return "loopback"
