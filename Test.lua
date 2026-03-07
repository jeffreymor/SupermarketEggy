local TAG = "[Test]"
local Timer = require("Utils.Timer")
local SecondTimer = require("Utils.SecondTimer")
local UnitUtils = require("Utils.UnitUtils")
local GuiUtils = require("Utils.GuiUtils")
local Prefab = require("Data.Prefab")
local UINodes = require("Data.UINodes")

local function test()
    LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, UINodes.TestImage, 1 }, function(eventName, actor, data)
        print(TAG, "TestImage touched! eventName:", eventName, "actor:", actor, "data:", data)
    end)
    --eventName: {ET_EUI_NODE_TOUCH_EVENT, 1519736575|1878224505, 1}
    --actor { role="CampRole<1>", eui_node_id="1519736575|1878224505"}
end

-- local function test()
--     for _, role in ipairs(GameAPI.get_all_valid_roles()) do
--         GuiUtils.setImage(UINodes.TestImage, GameAPI.get_role(1).get_head_icon())
--         local timer = Timer.new(2, true, 0)
--         local isShowing = true
--         timer:setTimeEndCb(function()
--             if not isShowing then
--                 GuiUtils.setImage(UINodes.TestImage, GameAPI.get_role(1).get_head_icon())
--                 GlobalAPI.show_tips("显示头像！", 3.0) -- 显示提示，持续3秒
--             else
--                 GuiUtils.setImage(UINodes.TestImage, 1862446592)
--                 GlobalAPI.show_tips("隐藏头像！", 3.0) -- 显示提示，持续3秒
--             end
--             isShowing = not isShowing
--         end)
--         timer:start()
--     end
-- end

test()