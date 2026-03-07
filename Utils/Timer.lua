-- 引入类工具
local class = require("Utils.ClassUtils").class

local TAG = "[Timer]"

-- 定义Timer类
---@class Timer
---@field new fun(duration : number, repeatExec? : boolean, repeatCount? : integer): Timer
---@field start fun(self) : integer -- 启动计时器，返回Timer的timerId
---@field cancel fun(self) -- 取消计时器
---@field setTimeEndCb fun(self, callback: function, ...): nil -- 设置时间结束回调，callback为回调函数，...为回调函数参数
local Timer = class("Timer")

function Timer:ctor(duration, repeatExec, repeatCount)
    self._duration = duration
    self._repeat = repeatExec or false
    self._repeatCount = repeatCount or 0 -- 0表示无限次
    -- self.elapsedTime = 0.0
    self._timerId = nil
    self._executions = 0 -- 已执行次数
    self._active = false
    self._allDone = false
    self._timeEndCb = nil
end

function Timer:start()
    --只能启动一次
    assert(not self._active and not self._allDone, TAG .. " Timer is already active or done!")
    assert(self._duration ~= nil and self._duration > 0, TAG .. " Timer duration is invalid!")
    assert(self._timeEndCb ~= nil, TAG .. " Timer time end callback not set!")

    self._active = true
    -- self.elapsedTime = 0.0
    if not self._repeat then
        self._timerId = LuaAPI.global_register_trigger_event(
            { EVENT.TIMEOUT, self._duration },
            self._timeEndCb)
    else
        self._timerId = LuaAPI.global_register_trigger_event(
            { EVENT.REPEAT_TIMEOUT, self._duration },
            self._timeEndCb)
    end
   
    return self._timerId
end

function Timer:cancel()
    if self._active then
        self._active = false
        if self._timerId ~= nil then
            LuaAPI.global_unregister_trigger_event(self._timerId)
            self._timerId = nil
        end
    end
    self._timeEndCb = nil
end

function Timer:setTimeEndCb(callback, ...)
    local args = table.pack(...)
    self._timeEndCb = function()
        if not self._active then
            if self._timerId ~= nil then
                LuaAPI.global_unregister_trigger_event(self._timerId)
                self._timerId = nil
            end
            self._timeEndCb = nil
            return
        end
        
        self._executions = self._executions + 1
        if self._repeat then
            if self._repeatCount > 0 and self._executions >= self._repeatCount then
                self._allDone = true
            end
        else
            self._allDone = true
        end
        if self._allDone then
            self._active = false
            if self._timerId ~= nil then
                LuaAPI.global_unregister_trigger_event(self._timerId)
                self._timerId = nil
            end
            self._timeEndCb = nil
        end

        callback(table.unpack(args))
    end
end

return Timer