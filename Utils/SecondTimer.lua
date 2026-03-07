local class = require("Utils.ClassUtils").class
local Timer = require("Utils.Timer")

local TAG = "[SecondTimer]"

---@class SecondTimer 带秒级回调的定时器
---@field new fun(totalSeconds: integer?, onTick: fun(remaining: integer|nil, total: integer|nil), onDone?: fun()): SecondTimer
---@field start fun(self): integer? -- 启动计时器，返回Timer的timerId
---@field cancel fun(self) -- 取消计时器
---@field getElapsed fun(self): integer -- 获取已经过去的秒数
---@field isActive fun(self): boolean -- 获取计时器是否仍在运行
local SecondTimer = class("SecondTimer")

function SecondTimer:ctor(totalSeconds, onTick, onDone)
    self._totalSeconds = totalSeconds
    self._onTick = onTick
    self._onDone = onDone
    self._elapsed = 0
    self._timer = nil
    self._active = false
end

function SecondTimer:start()
    assert(not self._active, TAG .. " is already active!")
    assert(self._onTick ~= nil, TAG .. " onTick callback not set!")

    local total = self._totalSeconds
    local repeatCount = 0
    if total ~= nil and total > 0 then
        repeatCount = total
    end

    local function emitTick()
        local remaining = nil
        if total ~= nil and total > 0 then
            remaining = total - self._elapsed
            if remaining < 0 then
                remaining = 0
            end
        end
        self._onTick(remaining, total)
    end

    local timer = Timer.new(1, true, repeatCount)
    timer:setTimeEndCb(function()
        self._elapsed = self._elapsed + 1
        emitTick()

        if repeatCount > 0 and self._elapsed >= repeatCount then
            self._active = false
            if self._onDone ~= nil then
                self._onDone()
            end
        end
    end)

    self._timer = timer
    self._active = true

    emitTick()
    if not self._active or self._timer == nil then
        return nil
    end

    return timer:start()
end

function SecondTimer:cancel()
    self._active = false
    if self._timer ~= nil then
        self._timer:cancel()
        self._timer = nil
    end
end

function SecondTimer:getElapsed()
    return self._elapsed
end

function SecondTimer:isActive()
    return self._active
end

return SecondTimer
