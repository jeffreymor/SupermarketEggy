local ShoppingCartUI = require("ShoppingCartUI")

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    require("Test")
    -- require("UICheck")
    ShoppingCartUI.init()
end)
