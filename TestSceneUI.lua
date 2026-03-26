local TestSceneUI = {}

local TAG = "[TestSceneUI]"
local Prefab = require("Data.Prefab")
local UINodes = require("Data.UINodes")

local SCENE_UI_OFFSET = math.Vector3(0.0, 3.0, 0.0) -- SceneUI 本地偏移（create_scene_ui_bind_unit _offset_pos，单位：米）
local SCENE_UI_DURATION = -1.0 -- SceneUI 持续时长（create_scene_ui_bind_unit _duration，-1 常驻）
local SCENE_UI_SOCKET = Enums.ModelSocket.socket_body -- SceneUI 绑定挂点（create_scene_ui_bind_unit _socket_name）

local inited = false
local activeSceneUILayer = nil

---@param sceneUiLayer E3DLayer
local function registerDeployButtonTouch(sceneUiLayer)
    local deployBtnNodeId = UINodes.DeployBtn
    if deployBtnNodeId == nil then
        print(TAG, "missing ui node: DeployBtn")
        return
    end

    local deployBtnNode = GameAPI.get_eui_node_at_scene_ui(sceneUiLayer, deployBtnNodeId)
    if deployBtnNode == nil then
        print(TAG, "missing scene ui node: DeployBtn")
        return
    end

    LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, deployBtnNode, 1 }, function(_, actor, data)
        if data == nil then
            print(TAG, "touch data nil: DeployBtn", actor)
            return
        end
        print(TAG, "DeployBtn touched, actor:", actor, "node:", data.eui_node_id)
    end)
    print(TAG, "register DeployBtn touch:", deployBtnNode)
end

---@return boolean
local function createSceneUI()
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
    local sceneUiLayer = testUnit.create_scene_ui_bind_unit(
        Prefab.scene_eui.DeploySceneUI,
        SCENE_UI_SOCKET,
        SCENE_UI_OFFSET,
        SCENE_UI_DURATION,
        true,
        true
    )

    if sceneUiLayer == nil then
        print(TAG, "create scene ui failed")
        GlobalAPI.show_tips("SceneUI 创建失败", 3.0)
        return false
    end

    activeSceneUILayer = sceneUiLayer
    registerDeployButtonTouch(sceneUiLayer)
    print(TAG, "create scene ui success")
    GlobalAPI.show_tips("SceneUI 创建成功", 2.0)
    return true
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
        createSceneUI()
    end)

    inited = true
end

return TestSceneUI
