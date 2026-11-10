# 验证 ENet 局域网传输（P11-C1-a）
#   1) host / join / 连接信号 / local_id 语义（host=1、client=随机大整数）
#   2) get_peers：ENetMultiplayerPeer 本身没有该方法，必须由信号维护
#   3) 定向收发 / 广播 / 8KB 分片 / 100 包可靠有序
#   4) 三人房间、客人断线、端口占用、连不上（异步语义）
#   5) close 之后重复 poll 不能炸（引擎在实例失活时 poll 会报错）
# 运行：godot --headless --path . --script tests/verify_enet_transport.gd
extends SceneTree

const ENetTransportScript = preload("res://scripts/net/ENetTransport.gd")
const NetTransportScript = preload("res://scripts/net/NetTransport.gd")

const PORT_CANDIDATES = [47811, 47812, 47813]
const CONNECT_TIMEOUT_MS = 5000
const IO_TIMEOUT_MS = 3000

var fails: int = 0
var checks: int = 0
var events: Array = []      # [{"t": 端点名, "k": conn/disc/pkt, "id": peer_id, "data": ...}]


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _finish() -> void:
	if fails == 0:
		print("ALL ENET TRANSPORT TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d ENET TRANSPORT TESTS FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)


# 没有帧循环：手动 pump 直到条件满足或超时
func _pump(peers: Array, cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for p in peers:
			if p != null:
				p.poll()
		if bool(cond.call()):
			return true
		OS.delay_msec(3)
	return false


# 给某个传输实例挂事件记录器（便于按端点断言）
func _tap(name: String, t) -> void:
	t.peer_connected.connect(func(pid): events.append({"t": name, "k": "conn", "id": int(pid)}))
	t.peer_disconnected.connect(func(pid): events.append({"t": name, "k": "disc", "id": int(pid)}))
	t.packet_received.connect(func(pid, data):
		events.append({"t": name, "k": "pkt", "id": int(pid), "data": data}))


func _has(name: String, kind: String, id: int) -> bool:
	for e in events:
		if String(e["t"]) == name and String(e["k"]) == kind and int(e["id"]) == id:
			return true
	return false


func _count(name: String, kind: String) -> int:
	var n := 0
	for e in events:
		if String(e["t"]) == name and String(e["k"]) == kind:
			n += 1
	return n


func _packets(name: String) -> Array:
	var out: Array = []
	for e in events:
		if String(e["t"]) == name and String(e["k"]) == "pkt":
			out.append(e)
	return out


func _run() -> void:
	var a = ENetTransportScript.new()      # 房主
	var b = ENetTransportScript.new()      # 客人 1
	var c = ENetTransportScript.new()      # 客人 2
	_tap("A", a)
	_tap("B", b)
	_tap("C", c)

	# ---- 1. 开房（候选端口逐个试，避免被占用导致误报）----
	var port := -1
	for p in PORT_CANDIDATES:
		if a.host(int(p), 4) == 0:
			port = int(p)
			break
	_check(port > 0, "成功开房（端口 %d）" % port)
	if port <= 0:
		_finish()
		return
	_check(a.mode == NetTransportScript.Mode.HOST, "host 后 mode == HOST")
	_check(a.local_id == 1, "host 的 local_id == 1")
	_check(a.get_transport_name() == "enet", "get_transport_name() == enet")
	_check(a.get_peers().is_empty(), "空房间 get_peers() 为空")
	_check(not a.is_connected_to(1), "主机自己不算自己的 peer")

	# ---- 2. 客人加入 ----
	_check(b.join("127.0.0.1", port) == 0, "join 返回 0")
	_check(b.mode == NetTransportScript.Mode.CLIENT, "join 后 mode == CLIENT")
	_check(b.local_id == 0, "连上之前 local_id 还是 0（create_client 是异步的）")

	var connected := _pump([a, b],
			func(): return a.get_peers().size() == 1 and b.local_id > 0, CONNECT_TIMEOUT_MS)
	_check(connected, "握手完成（双方 poll 后连上）")
	if not connected:
		a.close()
		b.close()
		_finish()
		return

	var b_id: int = b.local_id
	_check(b_id != 1, "客人的 peer_id 不是 1（ENet 随机分配）")
	_check(b_id > 1, "客人的 peer_id 是正整数 uid（实测为随机 32 位）")
	_check(_has("A", "conn", b_id), "主机收到 peer_connected(客人 uid)")
	_check(_has("B", "conn", 1), "客人收到 peer_connected(1)")
	_check(a.get_peers() == [b_id], "主机 get_peers() == [客人 uid]")
	_check(b.get_peers() == [1], "客人 get_peers() == [1]")
	_check(a.is_connected_to(b_id) and b.is_connected_to(1), "is_connected_to 双向为真")
	_check(not a.is_connected_to(999999), "is_connected_to(不存在的 peer) 为假")

	# ---- 3. 定向收发 ----
	var payload := PackedByteArray([1, 2, 3, 250])
	_check(a.send_to(b_id, payload) == 0, "主机 send_to(客人) 返回 0")
	_check(_pump([a, b], func(): return _count("B", "pkt") >= 1, IO_TIMEOUT_MS), "客人收到数据包")
	var pk_b: Array = _packets("B")
	_check(pk_b.size() == 1 and int(pk_b[0]["id"]) == 1, "数据包来源 peer_id == 1")
	_check(pk_b.size() == 1 and pk_b[0]["data"] == payload, "数据包内容逐字节一致（含 250 的高位字节）")

	_check(b.send_to(1, PackedByteArray([9, 8, 7])) == 0, "客人 send_to(主机) 返回 0")
	_check(_pump([a, b], func(): return _count("A", "pkt") >= 1, IO_TIMEOUT_MS), "主机收到数据包")
	var pk_a: Array = _packets("A")
	_check(pk_a.size() == 1 and int(pk_a[0]["id"]) == b_id, "主机收到的来源 == 客人 uid")
	_check(a.send_to(999999, payload) == -1, "send_to(不存在的 peer) 返回 -1")

	# ---- 4. 广播 ----
	events.clear()
	_check(a.broadcast(PackedByteArray([42])) == 0, "主机 broadcast 返回 0")
	_check(_pump([a, b], func(): return _count("B", "pkt") >= 1, IO_TIMEOUT_MS), "主机广播 → 客人收到")
	events.clear()
	_check(b.broadcast(PackedByteArray([43])) == 0, "客人 broadcast 返回 0")
	_check(_pump([a, b], func(): return _count("A", "pkt") >= 1, IO_TIMEOUT_MS), "客人广播 → 主机收到")

	# ---- 5. 8KB 分片 ----
	events.clear()
	var big := PackedByteArray()
	big.resize(8192)
	for i in range(big.size()):
		big[i] = i % 251
	_check(b.send_to(1, big) == 0, "客人发 8KB 包返回 0")
	_pump([a, b], func(): return _count("A", "pkt") >= 1, IO_TIMEOUT_MS)
	var pk_big: Array = _packets("A")
	_check(pk_big.size() == 1 and pk_big[0]["data"] == big, "8KB 包完整到达（ENet 自动分片）")

	# ---- 6. 100 包可靠有序 ----
	events.clear()
	for i in range(100):
		b.send_to(1, PackedByteArray([i]))
	_pump([a, b], func(): return _count("A", "pkt") >= 100, IO_TIMEOUT_MS)
	var pk_seq: Array = _packets("A")
	_check(pk_seq.size() == 100, "连发 100 包全部到达")
	var ordered := pk_seq.size() == 100
	if ordered:
		for i in range(100):
			var d = pk_seq[i]["data"]
			if d.size() != 1 or int(d[0]) != i:
				ordered = false
				break
	_check(ordered, "100 包严格按发送顺序到达（RELIABLE 有序）")

	# ---- 7. 三人房间 ----
	_check(c.join("127.0.0.1", port) == 0, "第三端 join 返回 0")
	var three_ok := _pump([a, b, c],
			func(): return a.get_peers().size() == 2 and c.local_id > 0, CONNECT_TIMEOUT_MS)
	_check(three_ok, "三人房间握手完成")
	var c_id: int = c.local_id
	_check(c_id != b_id, "两个客人的 uid 互不相同")
	var expect: Array = [b_id, c_id]
	expect.sort()
	_check(a.get_peers() == expect, "主机 get_peers() 两位客人且升序稳定")
	events.clear()
	a.broadcast(PackedByteArray([7]))
	_pump([a, b, c], func(): return _count("B", "pkt") >= 1 and _count("C", "pkt") >= 1, IO_TIMEOUT_MS)
	_check(_count("B", "pkt") >= 1 and _count("C", "pkt") >= 1, "广播覆盖全部客人")

	# ---- 8. 客人主动断线 ----
	events.clear()
	b.close()
	_check(b.mode == NetTransportScript.Mode.NONE, "客人 close 后 mode == NONE")
	_check(b.get_peers().is_empty(), "客人 close 后 get_peers 为空")
	_check(b.local_id == 1, "客人 close 后 local_id 归位 1")
	# 引擎在实例失活后 poll 会报错，实现里先把 _peer 置 null —— 这里验证确实安全
	b.poll()
	b.poll()
	_check(true, "close 之后重复 poll 不抛异常（执行到此处即未崩）")
	_check(_pump([a, c], func(): return _has("A", "disc", b_id), CONNECT_TIMEOUT_MS),
			"主机收到 peer_disconnected(客人 uid)")
	_check(not a.is_connected_to(b_id), "主机不再认为该 peer 在线")
	_check(a.get_peers() == [c_id], "主机 get_peers 只剩第三人")

	# ---- 9. 端口占用 ----
	var d = ENetTransportScript.new()
	_check(d.host(port, 4) == -1, "同端口再开房间返回 -1（端口被占用）")
	_check(d.mode == NetTransportScript.Mode.NONE, "开房失败后 mode 保持 NONE")
	d.close()

	# ---- 10. 连不上（异步语义）----
	var e = ENetTransportScript.new()
	_tap("E", e)
	_check(e.join("127.0.0.1", port + 50) == 0, "join 到无人监听的端口仍返回 0（异步）")
	var ghost := _pump([e], func(): return _count("E", "conn") > 0, 800)
	_check(not ghost, "800ms 内没有 peer_connected（未把「发起」当成「已连接」）")
	_check(e.local_id == 0, "没连上时 local_id 保持 0")
	_check(e.get_peers().is_empty(), "没连上时 get_peers 为空")
	e.close()
	_check(e.join("", port) == -1, "空地址 join 直接返回 -1")

	# ---- 11. 收尾 ----
	c.close()
	a.close()
	_check(a.mode == NetTransportScript.Mode.NONE, "主机 close 后 mode == NONE")
	_check(a.get_peers().is_empty(), "主机 close 后 get_peers 为空")
	_finish()
