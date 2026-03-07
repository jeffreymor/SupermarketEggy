-- 引入类工具
local class = require("Utils.ClassUtils").class

-- 定义TriggerAreaHandler类
---@class TriggerAreaHandler
---@field new fun(triggerArea, enterCallback: fun(role: Role), leaveCallback: fun(role: Role)): TriggerAreaHandler
local TriggerAreaHandler = class("TriggerAreaHandler")

-- 构造函数：初始化触发区域处理器
-- @param triggerArea 触发区域
-- @param enterCallback 进入区域时的回调函数
-- @param leaveCallback 离开区域时的回调函数
function TriggerAreaHandler:ctor(triggerArea, enterCallback, leaveCallback)
	-- 保存触发区域引用
	self.triggerArea = triggerArea
	-- 获取触发区域的单位ID
	local triggerAreaUnitId = LuaAPI.get_unit_id(triggerArea)

	-- 注册玩家进入触发区域的事件
	LuaAPI.global_register_trigger_event(
		{ EVENT.ANY_LIFEENTITY_TRIGGER_SPACE, Enums.TriggerSpaceEventType.ENTER, triggerAreaUnitId },
		function(_, _, data)
			-- 获取进入区域的角色
			local character = data.event_unit
			local role = character.get_role()
			-- 调用进入回调函数
			enterCallback(role)
		end
	)

	-- 注册玩家离开触发区域的事件
	LuaAPI.global_register_trigger_event(
		{ EVENT.ANY_LIFEENTITY_TRIGGER_SPACE, Enums.TriggerSpaceEventType.LEAVE, triggerAreaUnitId },
		function(_, _, data)
			-- 获取离开区域的角色
			local character = data.event_unit
			local role = character.get_role()
			-- 调用离开回调函数
			leaveCallback(role)
		end
	)
end

-- 返回TriggerAreaHandler类
return TriggerAreaHandler

