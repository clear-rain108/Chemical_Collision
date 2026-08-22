# 临时验证脚本3：验证 GameManager.log_messages 属性转发到 GameLogger
extends SceneTree

func _init():
	var GameManagerScript = load("res://scripts/GameManager.gd")
	var gm = GameManagerScript.new()
	assert(gm.logger != null, "logger 已创建")

	# 通过 log_messages 属性 append（旧接口）
	gm.log_messages.append("通过旧接口添加")
	assert(gm.logger.get_log_count() == 1, "logger 应有1条日志")
	assert(gm.logger.log_messages[0] == "通过旧接口添加", "日志内容一致")

	# flush_logs 转发到 logger
	var logs = gm.flush_logs()
	assert(logs.size() == 1, "flush_logs 返回1条")
	assert(gm.logger.get_log_count() == 0, "flush后为空")

	# logger.add_log 新接口
	gm.logger.add_log("通过新接口添加")
	assert(gm.log_messages.size() == 1, "log_messages getter 返回 logger 内容")

	print("PASS: log_messages 属性转发")
	quit(0)
