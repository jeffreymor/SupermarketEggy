local TestSceneUI = {}

local TAG = "[TestSceneUI]"
local Prefab = require("Data.Prefab")
local UINodes = require("Data.UINodes")
local Timer = require("Utils.Timer")

local SOCKET_TEST_INTERVAL_SEC = 1.0
local SCENE_UI_OFFSET = math.Vector3(0.0, 3.0, 0.0)

local MODEL_SOCKET_TEST_CASES = {
    { socket = Enums.ModelSocket.socket_abdomen, comment = "腹部" },
    { socket = Enums.ModelSocket.socket_belly, comment = "鱼腹" },
    { socket = Enums.ModelSocket.socket_body, comment = "身体" },
    { socket = Enums.ModelSocket.socket_calf_l, comment = "左小腿" },
    { socket = Enums.ModelSocket.socket_calf_r, comment = "右小腿" },
    { socket = Enums.ModelSocket.socket_chest, comment = "胸部" },
    { socket = Enums.ModelSocket.socket_claw_l, comment = "左钳" },
    { socket = Enums.ModelSocket.socket_claw_r, comment = "右钳" },
    { socket = Enums.ModelSocket.socket_eye_l, comment = "左眼" },
    { socket = Enums.ModelSocket.socket_eye_r, comment = "右眼" },
    { socket = Enums.ModelSocket.socket_fin_back, comment = "背后鳍" },
    { socket = Enums.ModelSocket.socket_fin_dorsal, comment = "背鳍" },
    { socket = Enums.ModelSocket.socket_fin_l, comment = "左鳍" },
    { socket = Enums.ModelSocket.socket_fin_lb, comment = "左后鳍" },
    { socket = Enums.ModelSocket.socket_fin_r, comment = "右鳍" },
    { socket = Enums.ModelSocket.socket_fin_rb, comment = "右后鳍" },
    { socket = Enums.ModelSocket.socket_fin_tail, comment = "尾鳍" },
    { socket = Enums.ModelSocket.socket_fin_ventral, comment = "腹鳍" },
    { socket = Enums.ModelSocket.socket_fin_ventral_l, comment = "左腹鳍" },
    { socket = Enums.ModelSocket.socket_fin_ventral_r, comment = "右腹鳍" },
    { socket = Enums.ModelSocket.socket_foot_l, comment = "左脚" },
    { socket = Enums.ModelSocket.socket_foot_lb, comment = "左后脚" },
    { socket = Enums.ModelSocket.socket_foot_lf, comment = "左前脚" },
    { socket = Enums.ModelSocket.socket_foot_lm, comment = "左中脚" },
    { socket = Enums.ModelSocket.socket_foot_r, comment = "右脚" },
    { socket = Enums.ModelSocket.socket_foot_rb, comment = "右后脚" },
    { socket = Enums.ModelSocket.socket_foot_rf, comment = "右前脚" },
    { socket = Enums.ModelSocket.socket_foot_rm, comment = "右中脚" },
    { socket = Enums.ModelSocket.socket_forearm_l, comment = "左臂" },
    { socket = Enums.ModelSocket.socket_forearm_r, comment = "右臂" },
    { socket = Enums.ModelSocket.socket_hand_l, comment = "左手" },
    { socket = Enums.ModelSocket.socket_hand_r, comment = "右手" },
    { socket = Enums.ModelSocket.socket_head, comment = "头部" },
    { socket = Enums.ModelSocket.socket_lowerarm_l, comment = "左小臂" },
    { socket = Enums.ModelSocket.socket_lowerarm_r, comment = "右小臂" },
    { socket = Enums.ModelSocket.socket_lowerlimb_lb, comment = "左后下肢" },
    { socket = Enums.ModelSocket.socket_lowerlimb_lf, comment = "左前下肢" },
    { socket = Enums.ModelSocket.socket_lowerlimb_rb, comment = "右后下肢" },
    { socket = Enums.ModelSocket.socket_lowerlimb_rf, comment = "右前下肢" },
    { socket = Enums.ModelSocket.socket_mouth, comment = "鱼嘴" },
    { socket = Enums.ModelSocket.socket_origin, comment = "底面中心点" },
    { socket = Enums.ModelSocket.socket_tail, comment = "尾巴" },
    { socket = Enums.ModelSocket.socket_tail_end, comment = "尾巴末端" },
    { socket = Enums.ModelSocket.socket_thigh_l, comment = "左大腿" },
    { socket = Enums.ModelSocket.socket_thigh_r, comment = "右大腿" },
    { socket = Enums.ModelSocket.socket_torso_b, comment = "躯干后部" },
    { socket = Enums.ModelSocket.socket_torso_f, comment = "躯干前部" },
    { socket = Enums.ModelSocket.socket_upperarm_l, comment = "左大臂" },
    { socket = Enums.ModelSocket.socket_upperarm_r, comment = "右大臂" },
    { socket = Enums.ModelSocket.socket_upperlimb_lb, comment = "左后上肢" },
    { socket = Enums.ModelSocket.socket_upperlimb_lf, comment = "左前上肢" },
    { socket = Enums.ModelSocket.socket_upperlimb_rb, comment = "右后上肢" },
    { socket = Enums.ModelSocket.socket_upperlimb_rf, comment = "右前上肢" },
    { socket = Enums.ModelSocket.socket_weapon_l, comment = "左手武器" },
    { socket = Enums.ModelSocket.socket_weapon_r, comment = "右手武器" },
}

local inited = false
local currentSocketIndex = 0
local socketTestRunning = false
local socketSequenceTimer = nil
local activeSceneUILayer = nil

---@param buttonNode EButton
---@param text string
local function setButtonTextForAllRoles(buttonNode, text)
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        role.set_button_text(buttonNode, text)
    end
end

local function stopSocketTest()
    if socketSequenceTimer ~= nil then
        socketSequenceTimer:cancel()
        socketSequenceTimer = nil
    end
    if activeSceneUILayer ~= nil then
        GameAPI.destroy_scene_ui(activeSceneUILayer)
        activeSceneUILayer = nil
    end
    socketTestRunning = false
    currentSocketIndex = 0
end

---@param socketName Enums.ModelSocket
---@param socketComment string
local function createSceneUIBySocket(socketName, socketComment)
    if activeSceneUILayer ~= nil then
        GameAPI.destroy_scene_ui(activeSceneUILayer)
        activeSceneUILayer = nil
    end

    local testUnit = LuaAPI.query_unit("TestDeployPart")
    if testUnit == nil then
        print(TAG, "missing unit: TestDeployPart")
        GlobalAPI.show_tips("缺少单位 TestDeployPart", 3.0)
        return false
    end

    ---@cast testUnit Obstacle
    local testSceneUI = testUnit.create_scene_ui_bind_unit(
        Prefab.scene_eui.DeploySceneUI, -- 预设
        socketName, -- 绑定骨骼点
        SCENE_UI_OFFSET, -- 偏移
        -1.0, -- 持续时间，-1 常驻
        true, -- 事件是否指向绑定者
        true -- 是否跟随单位显隐
    )

    if testSceneUI == nil then
        print(TAG, "create scene ui failed, socket:", socketName)
        GlobalAPI.show_tips("SceneUI 创建失败", 3.0)
        return false
    end
    activeSceneUILayer = testSceneUI

    local buttonNode = GameAPI.get_eui_node_at_scene_ui(testSceneUI, UINodes.DeployBtn)
    if buttonNode ~= nil then
        setButtonTextForAllRoles(buttonNode, socketComment)
    else
        print(TAG, "missing scene ui node: DeployBtn")
    end

    print(TAG, "create scene ui success, socket:", socketName, "comment:", socketComment)
    GlobalAPI.show_tips("SceneUI 创建成功: " .. socketComment, 2.0)
    return true
end

local function runSocketCaseAt(index)
    local socketCase = MODEL_SOCKET_TEST_CASES[index]
    if socketCase == nil then
        return
    end
    createSceneUIBySocket(socketCase.socket, socketCase.comment)
end

local function startSocketTest()
    if socketTestRunning then
        GlobalAPI.show_tips("ModelSocket 测试进行中", 2.0)
        return
    end

    local totalCount = #MODEL_SOCKET_TEST_CASES
    if totalCount == 0 then
        print(TAG, "no model socket test cases")
        return
    end

    socketTestRunning = true
    currentSocketIndex = 1
    runSocketCaseAt(currentSocketIndex)

    if totalCount == 1 then
        stopSocketTest()
        GlobalAPI.show_tips("ModelSocket 测试完成", 2.0)
        return
    end

    local remainingCount = totalCount - 1
    socketSequenceTimer = Timer.new(SOCKET_TEST_INTERVAL_SEC, true, remainingCount)
    socketSequenceTimer:setTimeEndCb(function()
        if not socketTestRunning then
            return
        end

        currentSocketIndex = currentSocketIndex + 1
        runSocketCaseAt(currentSocketIndex)

        if currentSocketIndex >= totalCount then
            stopSocketTest()
            GlobalAPI.show_tips("ModelSocket 测试完成", 2.0)
        end
    end)
    socketSequenceTimer:start()
end

function TestSceneUI.init()
    if inited then
        return
    end

    local node = UINodes.TestSceneUICreate
    if node == nil then
        print(TAG, "missing ui node: TestSceneUICreate")
        GlobalAPI.show_tips("缺少节点 TestSceneUICreate", 3.0)
        return
    end

    LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, node, 1 }, function(_, actor, data)
        if data == nil then
            print(TAG, "touch data nil: TestSceneUICreate", actor)
            return
        end
        startSocketTest()
    end)

    inited = true
end

return TestSceneUI
