-- 游戏启动将自动运行此文件

local TriggerAreaHandler = require("Utils.TriggerAreaHandler")
local StageLooper = require("Stage.StageLooper")
local RoundLooper = require("Stage.RoundLooper")
local InGameUiManager = require("UIHelpers.InGameGuiManager")
local StageEnterHandler = require("Stage.StageEnterHandler")
local QuestionHelper = require("QaA.QuestionHelper")
local AnswerHelper = require("QaA.AnswerHelper")
local PlayerManager = require("Player.PlayerManager")
local BlockHelper = require("Others.BlockHelper")
local NotificationManager = require("Others.NotificationManager")
local LavaHelper = require("Others.LavaHelper")

G = {}

-- 游戏初始化事件
LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    StageLooper:init()
    RoundLooper:init()
    StageEnterHandler:init()
    StageLooper:setStageEnterHandler(StageEnterHandler)
    QuestionHelper:init()
    AnswerHelper:init()
    AnswerHelper:setRoundInfoProvider(function()
        return RoundLooper:getCurrentRoundInfo()
    end)
    InGameUiManager:init()
    PlayerManager:init()
    BlockHelper:init(PlayerManager)
    NotificationManager:init()
    LavaHelper:init()

    StageLooper:startStageLoop()
    
    require("Test")
end)


