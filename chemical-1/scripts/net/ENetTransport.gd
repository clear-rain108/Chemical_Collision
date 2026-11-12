# ============================================================
# ENetTransport.gd - 局域网 / Tailscale 直连传输（P11-C1-a）
# 用法（与 LoopbackTransport 完全一致）：
#   var t = ENetTransportScript.new()
#   t.peer_connected.connect(...)
#   t.host(47800, 4)             # 房主：local_id = 1
#   t.join("192.168.1.7", 47800) # 客人：local_id 要等连上才确定
#   # 每个渲染帧 t.poll()
#
# 关键设计：**不挂到 multiplayer.multiplayer_peer**
#   ENetMultiplayerPeer 底层的 put_packet / get_packet / set_target_peer 可以直接
#   收发原始包；一旦赋给 multiplayer.multiplayer_peer，就会被 SceneMultiplayer
#   接管，只能走 @rpc / 场景复制，与 NetTransport 的 PackedByteArray 抽象不兼容。
#
# 实测结论（Godot 4.7.2，2026-11）：
#   - ENetMultiplayerPeer **没有 get_peers()**，peer 集合只能靠
#     peer_connected / peer_disconnected 信号自己维护（本文件用 _peers 字典）
#   - 客人的 peer_id 是**随机 32 位整数**（如 754867515），只有主机恒为 1；
#     上层绝不能假设 peer_id = 座位号，必须走 peer_id ↔ seat 映射表
#   - close() 之后**绝不能再 poll()**（引擎会刷 "multiplayer instance isn't active"），
#     所以 close() 先把 _peer 置 null 再关闭
#   - 8KB 包自动分片、100 连包可靠有序（TRANSFER_MODE_RELIABLE）
#   - 同端口二次 create_server 返回 20（ERR_CANT_CREATE）→ host() 转成 -1
# ============================================================
extends "res://scripts/net/NetTransport.gd"

# 默认端口：局域网固定端口，方便房主直接报给客人（随机端口对局域网不友好）
const DEFAULT_PORT := 47800

var _peer: ENetMultiplayerPeer = null
var _pending: Array = []            # [["connected"/"packet"/"disconnected", id, data], ...]
var _peers: Dictionary = {}         # peer_id → true（ENetMultiplayerPeer 无 get_peers）
var _was_connected: bool = false    # 曾经连上过：区分「根本连不上」与「连上后又断了」


func host(port: int, max_players: int = 4) -> int:
	close()
	var peer := ENetMultiplayerPeer.new()
	# 房主自己不算 client：max_players=4 → ENet 最多接 3 个客人
	var err := peer.create_server(port, maxi(1, max_players - 1))
	if err != OK:
		return -1
	_bind(peer)
	mode = Mode.HOST
	local_id = 1
	return 0


func join(address: String, port: int) -> int:
	close()
	var addr := address.strip_edges()
	if addr == "":
		return -1
	var peer := ENetMultiplayerPeer.new()
	# create_client 是异步的：返回 0 只代表「发起成功」，真正连上要看 peer_connected
	if peer.create_client(addr, port) != OK:
		return -1
	_bind(peer)
	mode = Mode.CLIENT
	local_id = 0        # 连上后由 poll() 用 get_unique_id() 填（随机 32 位，不是 2）
	return 0


func close() -> void:
	if _peer != null:
		# 先摘引用再 close：close 之后调用 poll() 会让引擎报错
		var peer := _peer
		_peer = null
		peer.close()
	_peers.clear()
	_pending.clear()
	_was_connected = false
	mode = Mode.NONE
	local_id = 1


# 每个渲染帧调用一次：把底层网络事件派发成信号（不要在 send 里同步触发）
func poll() -> void:
	if _peer == null:
		return
	# 对端整机消失（房主杀进程 / 断网 / 关服）时，引擎会把 ENet 置成「未激活」：
	# 之后再 poll() / put_packet() 只会每帧刷
	# "multiplayer instance isn't currently active"，而且客人**永远等不到掉线事件**
	# （peer_disconnected 只有服务端才会收到）。这种情况要补派发一次「对端掉线」，
	# 客人的会话才能立刻收尾；D21 的心跳只是兜底。
	# 「未激活」= 状态已经是 DISCONNECTED（含从没连上的情形），两种都不该再 poll()。
	var dead := _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
	if not dead:
		_peer.poll()
		# 客人：连上后才拿得到自己的随机 id。抢在派发信号之前填好，
		# 上层在 peer_connected 回调里读 local_id 就已经是有效值。
		if mode == Mode.CLIENT and local_id <= 0 \
				and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			local_id = _peer.get_unique_id()
	# 收包必须排在「判失活」之后、收尾之前：引擎在客人掉线时只是把 peer 置为
	# 未激活，**已经收进队列的包还在**（房主 close() 前刷出去的 BYE 就在里面）。
	# 抢在 _reap_inactive() 前面搬走，客人才能拿到「房主结束了本局」而不是笼统的掉线。
	while _peer != null and _peer.get_available_packet_count() > 0:
		# 必须先取 peer 再取包：get_packet() 会推进接收队列
		var from := _peer.get_packet_peer()
		var data := _peer.get_packet()
		if data.size() > 0:
			_pending.append(["packet", from, data])
	# 只有「连上过又断了」才补派发掉线：IP 写错 / 端口没人听时 _was_connected 恒为 false，
	# 那种情况要把判断留给 UI 的连接超时提示，不能被这里一帧就关掉会话。
	if dead and _was_connected:
		_reap_inactive()        # 内部补派发 disconnected 并统一 drain
		return
	_drain()


func send_to(peer_id: int, data: PackedByteArray) -> int:
	if _peer == null or not _peers.has(peer_id):
		return -1
	# set_target_peer 是持久状态：每次发送前重设，不依赖上一次的残留值
	_peer.set_target_peer(peer_id)
	return 0 if _peer.put_packet(data) == OK else -1


func broadcast(data: PackedByteArray) -> int:
	if _peer == null:
		return -1
	_peer.set_target_peer(0)    # 0 = 所有已连接 peer（主机自己不会收到）
	return 0 if _peer.put_packet(data) == OK else -1


func get_peers() -> Array:
	var out: Array = []
	for pid in _peers:
		out.append(int(pid))
	out.sort()      # 字典遍历顺序不稳定；排序保证上层拿到确定性结果
	return out


func is_connected_to(peer_id: int) -> bool:
	return _peer != null and _peers.has(peer_id)


func get_transport_name() -> String:
	return "enet"


# ---- 内部 ----
func _bind(peer: ENetMultiplayerPeer) -> void:
	# 事件流必须可靠有序：丢一包 = 双方状态分叉
	peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	peer.set_transfer_channel(0)
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	_peers.clear()
	_pending.clear()
	_was_connected = false
	_peer = peer


# 底层 ENet 已被引擎置为未激活：把「对端掉线」补进待派发队列再收尾。
# 顺序很重要 —— 先摘 _peer 再 close()，否则之后的 poll() 会刷引擎报错。
func _reap_inactive() -> void:
	var peer := _peer
	_peer = null
	var gone: Array = []
	if mode == Mode.CLIENT:
		gone.append(1)                  # 客人视角：唯一对端就是房主（peer_id 恒为 1）
	else:
		for pid in _peers.keys():
			gone.append(int(pid))
	_peers.clear()
	for pid in gone:
		_pending.append(["disconnected", int(pid)])
	mode = Mode.NONE
	local_id = 1
	_was_connected = false
	if peer != null:
		peer.close()
	_drain()


func _on_peer_connected(peer_id: int) -> void:
	var pid := int(peer_id)
	if _peers.has(pid):
		return
	_was_connected = true
	_peers[pid] = true
	_pending.append(["connected", pid])


func _on_peer_disconnected(peer_id: int) -> void:
	var pid := int(peer_id)
	if not _peers.has(pid):
		return
	_peers.erase(pid)
	_pending.append(["disconnected", pid])


func _drain() -> void:
	while not _pending.is_empty():
		var e = _pending.pop_front()
		match String(e[0]):
			"connected":
				peer_connected.emit(int(e[1]))
			"packet":
				packet_received.emit(int(e[1]), e[2])
			"disconnected":
				peer_disconnected.emit(int(e[1]))
