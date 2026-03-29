class_name Util
extends Node

static func map_dict_values(dict: Dictionary, function: Callable) -> Dictionary:
	var result = {}
	for key in dict:
		var func_result = function.call(dict[key])
		if not func_result:
			print("map_dict_values: function call failed for key " + key)
			continue
		result[key] = func_result
	return result

static func is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func is_string_array(v: Variant) -> bool:
	# 1. 首先必须是一个数组
	if typeof(v) != TYPE_ARRAY:
		return false
	
	# 2. 检查数组的内置类型约束
	# TYPE_STRING 的枚举值是 4
	return v.get_typed_builtin() == TYPE_STRING
