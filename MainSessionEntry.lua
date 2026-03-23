local MainSessionEntry = {}

local TAG = "[Main]"
local SESSION_BEGIN_MARKER = "========================session begin========================" -- 会话起始标记（日志检索锚点）

function MainSessionEntry.init()
    print(TAG, SESSION_BEGIN_MARKER)
end

return MainSessionEntry
