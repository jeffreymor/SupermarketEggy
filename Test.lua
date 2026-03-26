local TAG = "[Test]"
local Timer = require("Utils.Timer")
local SecondTimer = require("Utils.SecondTimer")
local UnitUtils = require("Utils.UnitUtils")
local GuiUtils = require("Utils.GuiUtils")
local Prefab = require("Data.Prefab")
local UINodes = require("Data.UINodes")

local function test()
    local testUnit = LuaAPI.query_unit("TestDeployPart")
    local eventNames = {"Test1", "Test2", "Test3"}
    for _, eventName in ipairs(eventNames) do
        print(TAG, "registering event:", eventName)
        LuaAPI.global_register_custom_event(eventName, function(param1, param2, data)
            print(TAG, eventName, "event received:", param1, param2, data)
        end)
        LuaAPI.unit_register_custom_event(testUnit, eventName, function(param1, param2, data)
            print(TAG, eventName, "event received on unit:", param1, param2, data)
        end)
    end

    LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, UINodes.TestBtn, 1 }, function(_, actor, data)
        if data == nil then
            print(TAG, "touch data nil: DeployBtn", actor)
            return
        end
        print(TAG, "deploy button touched", "actor:", actor)
    end)
end

test()
