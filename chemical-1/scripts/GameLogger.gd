# ============================================================
# GameLogger.gd - 信息记录模块
# 职责：统一游戏日志的写入、缓存与获取
# 供 UI 层订阅显示；规则层只需调用 add_log 无需关心展示
# ============================================================
extends RefCounted

var log_messages: Array = []   # 待消费日志（flush 后清空）

# 添加一条日志
func add_log(msg: String) -> void:
	log_messages.append(msg)

# 追加日志（与 add_log 等价，便于语义化调用）
func append_log(msg: String) -> void:
	add_log(msg)

# 获取并清空全部待消费日志
func flush_logs() -> Array:
	var logs = log_messages.duplicate()
	log_messages.clear()
	return logs

# 当前待消费日志数量
func get_log_count() -> int:
	return log_messages.size()

# 清空全部日志
func clear_logs() -> void:
	log_messages.clear()
