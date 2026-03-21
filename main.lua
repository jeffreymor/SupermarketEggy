local ShoppingCartUI = require("ShoppingCartUI")
local TestCreateFrontBox = require("TestCreateFrontBox")

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    -- require("UICheck")
    -- ShoppingCartUI.init()
    TestCreateFrontBox.init()
    -- require("Test")
end)
