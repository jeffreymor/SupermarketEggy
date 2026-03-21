local TestCreateFrontBox = {}

local TAG = "[TestCreateFrontBox]"
local Prefab = require("Data.Prefab")
local UINodes = require("Data.UINodes")

local DEBUG_LOG_ENABLED = false -- 排障日志开关（默认关闭；定位箱子互动链路时再开启）
local TEST_BOX_ID = Prefab.unit.FinalBox -- 箱子模型ID（Prefab.unit）
local TEST_ITEM_ID = Prefab.unit.TestItem -- 箱内物品模型ID（Prefab.unit）
local DEFAULT_QUATERNION = math.Quaternion(0.0, 0.0, 0.0) -- 默认旋转（DisplayComp.bind_model _rot）
local DEFAULT_SCALE = math.Vector3(1.0, 1.0, 1.0) -- 默认缩放（DisplayComp.bind_model/create_unit_with_scale _scale）
local BOX_SCALE = math.Vector3(1.0, 1.0, 1.0) -- 箱子缩放（DisplayComp.bind_model/create_unit_with_scale _scale）
local ITEM_LOCAL_OFFSET = math.Vector3(0.0, 0.0, 0.0) -- item 相对箱子局部中心偏移（Unit.get_local_offset_position，单位待确认）
local ITEM_SIDE_DISTANCE = 1.0 -- item 左右间距（Enums.DirectionType.LEFT/RIGHT，单位待确认）
local ITEM_EXTRA_HEIGHT_OFFSET = 0.12 -- item 额外抬高偏移（+Y，单位待确认）
local BOX_BASE_POINT_OFFSET = math.Vector3(0.0, -0.6, 0.0) -- 箱子原点到底面的修正偏移（位置对齐，单位待确认）
local BOX_TARGET_POSITION_OFFSET = math.Vector3(0.0, 0.0, 0.0) -- 人物前方落点附加偏移（正负方向同世界坐标，单位待确认）
local CREATE_FORWARD_DISTANCE = 2.0 -- 箱子生成人物前方距离（Enums.DirectionType.FORWARD，单位待确认）
local FOLLOW_STACK_HEIGHT_STEP = 3.0 -- 头顶堆叠层高步长（DisplayComp.bind_model _offset.y，单位待确认）
local FOLLOW_SOCKET = Enums.ModelSocket.socket_head -- 绑定挂点（Enums.ModelSocket）
local BOX_LAYER_BASE_OFFSET = math.Vector3(0.0, 1.0, 0.0) -- 第 0 层箱子相对挂点基准偏移（DisplayComp.bind_model _offset，单位待确认）

local groundBoxStates = dict()
local roleFollowStates = dict()

---@alias Node string

local function debugLog(...)
    if not DEBUG_LOG_ENABLED then
        return
    end
    print(TAG, ...)
end

---@param targetUnits Unit[]|nil
---@param sourceUnits Unit[]|nil
local function appendUniqueUnits(targetUnits, sourceUnits)
    if targetUnits == nil or sourceUnits == nil then
        return
    end

    for _, sourceUnit in ipairs(sourceUnits) do
        local exists = false
        for _, targetUnit in ipairs(targetUnits) do
            if targetUnit == sourceUnit then
                exists = true
                break
            end
        end

        if not exists then
            targetUnits[#targetUnits + 1] = sourceUnit
        end
    end
end

---@param role Role|nil
---@return Character|nil
local function getRoleCtrlUnit(role)
    if role == nil then
        print(TAG, "missing role")
        return nil
    end

    local roleCtrlUnit = role.get_ctrl_unit()
    if roleCtrlUnit == nil then
        print(TAG, "missing ctrl unit, role:", role)
        return nil
    end

    return roleCtrlUnit
end

---@param roleCtrlUnit Character
---@return table
local function getOrCreateFollowState(roleCtrlUnit)
    local followState = roleFollowStates:get(roleCtrlUnit)
    if followState == nil then
        followState = {
            roleCtrlUnit = roleCtrlUnit,
            boxes = {},
        }
        roleFollowStates:set(roleCtrlUnit, followState)
    else
        followState.roleCtrlUnit = roleCtrlUnit
    end
    return followState
end

---@param roleCtrlUnit Character
local function clearFollowStateIfEmpty(roleCtrlUnit)
    local followState = roleFollowStates:get(roleCtrlUnit)
    if followState ~= nil and #followState.boxes == 0 then
        roleFollowStates:set(roleCtrlUnit, nil)
    end
end

---@param roleCtrlUnit Character
---@return Vector3
local function getGroundBoxPosition(roleCtrlUnit)
    local rolePosition = roleCtrlUnit.get_position()
    local forwardPosition = rolePosition + roleCtrlUnit.get_local_direction(Enums.DirectionType.FORWARD) * CREATE_FORWARD_DISTANCE
    return forwardPosition - BOX_BASE_POINT_OFFSET + BOX_TARGET_POSITION_OFFSET
end


---@param roleCtrlUnit Character
---@return Quaternion
local function getGroundBoxOrientation(roleCtrlUnit)
    return roleCtrlUnit.get_orientation()
end

---@param stackIndex integer
---@return Vector3, Vector3[]
local function getLayerOffsets(stackIndex)
    local boxOffset = BOX_LAYER_BASE_OFFSET + math.Vector3(0.0, stackIndex * FOLLOW_STACK_HEIGHT_STEP, 0.0)
    local itemCenterOffset = boxOffset + ITEM_LOCAL_OFFSET + math.Vector3(0.0, ITEM_EXTRA_HEIGHT_OFFSET, 0.0)
    return boxOffset, {
        itemCenterOffset,
        itemCenterOffset + math.Vector3(-ITEM_SIDE_DISTANCE, 0.0, 0.0),
        itemCenterOffset + math.Vector3(ITEM_SIDE_DISTANCE, 0.0, 0.0),
    }
end

---@param boxUnit Unit
---@return Vector3[]
local function getGroundItemPositions(boxUnit)
    local centerPosition = boxUnit.get_local_offset_position(ITEM_LOCAL_OFFSET + math.Vector3(0.0, ITEM_EXTRA_HEIGHT_OFFSET, 0.0))
    return {
        centerPosition,
        centerPosition + boxUnit.get_local_direction(Enums.DirectionType.LEFT) * ITEM_SIDE_DISTANCE,
        centerPosition + boxUnit.get_local_direction(Enums.DirectionType.RIGHT) * ITEM_SIDE_DISTANCE,
    }
end

---@param roleCtrlUnit Character
---@param bindIds string[]|nil
local function unbindModels(roleCtrlUnit, bindIds)
    if bindIds == nil then
        return
    end

    for _, bindId in ipairs(bindIds) do
        pcall(function()
            roleCtrlUnit.unbind_model(bindId)
        end)
    end
end

---@param itemUnits Unit[]|nil
local function destroyUnits(itemUnits)
    if itemUnits == nil then
        return
    end

    for _, itemUnit in ipairs(itemUnits) do
        if itemUnit ~= nil then
            GameAPI.destroy_unit(itemUnit)
        end
    end
end

---@param jointUnits JointAssistant[]|nil
local function destroyJointUnits(jointUnits)
    if jointUnits == nil then
        return
    end

    for _, jointUnit in ipairs(jointUnits) do
        if jointUnit ~= nil then
            debugLog("destroy joint unit:", jointUnit)
            GameAPI.destroy_unit(jointUnit)
        end
    end
end

---@param roleCtrlUnit Character
---@param stackIndex integer
---@return table|nil
local function createFollowLayer(roleCtrlUnit, stackIndex)
    local boxOffset, itemOffsets = getLayerOffsets(stackIndex)
    local boxBindId = roleCtrlUnit.bind_model(TEST_BOX_ID, FOLLOW_SOCKET, boxOffset, DEFAULT_QUATERNION, BOX_SCALE)
    if boxBindId == nil then
        print(TAG, "bind box failed at layer:", stackIndex)
        return nil
    end

    local itemBindIds = {}
    for itemIndex, itemOffset in ipairs(itemOffsets) do
        local itemBindId = roleCtrlUnit.bind_model(TEST_ITEM_ID, FOLLOW_SOCKET, itemOffset, DEFAULT_QUATERNION, DEFAULT_SCALE)
        if itemBindId == nil then
            unbindModels(roleCtrlUnit, { boxBindId })
            unbindModels(roleCtrlUnit, itemBindIds)
            print(TAG, "bind item failed at layer:", stackIndex, "index:", itemIndex)
            return nil
        end
        itemBindIds[#itemBindIds + 1] = itemBindId
    end

    return {
        boxBindId = boxBindId,
        itemBindIds = itemBindIds,
        stackIndex = stackIndex,
    }
end

---@param roleCtrlUnit Character
---@param followLayer table|nil
local function destroyFollowLayer(roleCtrlUnit, followLayer)
    if followLayer == nil then
        return
    end

    debugLog("destroy follow layer, stackIndex:", followLayer.stackIndex, "boxBindId:", followLayer.boxBindId)
    unbindModels(roleCtrlUnit, { followLayer.boxBindId })
    unbindModels(roleCtrlUnit, followLayer.itemBindIds)
end

---@param boxUnit Unit
---@return Unit[]|nil, JointAssistant[]|nil
local function createGroundItems(boxUnit)
    local itemOrientation = boxUnit.get_orientation()
    local itemPositions = getGroundItemPositions(boxUnit)
    local itemUnits = {}

    for _, itemPosition in ipairs(itemPositions) do
        local itemUnit = GameAPI.create_unit_with_scale(TEST_ITEM_ID, itemPosition, itemOrientation, DEFAULT_SCALE)
        if itemUnit == nil then
            destroyUnits(itemUnits)
            return nil
        end
        itemUnits[#itemUnits + 1] = itemUnit
    end

    local jointUnits = {}
    for _, itemUnit in ipairs(itemUnits) do
        local jointUnit = GameAPI.create_joint_assistant(Enums.JointAssistantKey.FIXED, boxUnit, itemUnit)
        if jointUnit == nil then
            destroyJointUnits(jointUnits)
            destroyUnits(itemUnits)
            return nil, nil
        end
        jointUnits[#jointUnits + 1] = jointUnit
    end

    return itemUnits, jointUnits
end

---@param roleCtrlUnit Character
---@return table|nil
local function createGroundBoxState(roleCtrlUnit)
    local boxUnit = GameAPI.create_unit_with_scale(
        TEST_BOX_ID,
        getGroundBoxPosition(roleCtrlUnit),
        getGroundBoxOrientation(roleCtrlUnit),
        BOX_SCALE
    )
    if boxUnit == nil then
        print(TAG, "create box failed")
        return nil
    end

    local itemUnits, jointUnits = createGroundItems(boxUnit)
    if itemUnits == nil or jointUnits == nil then
        print(TAG, "create ground items failed")
        GameAPI.destroy_unit(boxUnit)
        return nil
    end

    local groundBoxState = {
        boxUnit = boxUnit,
        itemUnits = itemUnits,
        jointUnits = jointUnits,
    }
    groundBoxStates:set(boxUnit, groundBoxState)
    debugLog("create ground box success, boxUnit:", boxUnit, "itemCount:", #itemUnits)
    return groundBoxState
end

---@param groundBoxState table|nil
local function destroyGroundBoxState(groundBoxState)
    if groundBoxState == nil then
        return
    end

    debugLog("destroy ground box state, boxUnit:", groundBoxState.boxUnit)
    local jointUnits = {}
    appendUniqueUnits(jointUnits, groundBoxState.jointUnits)
    if groundBoxState.boxUnit ~= nil then
        appendUniqueUnits(jointUnits, GameAPI.get_joint_assistants(groundBoxState.boxUnit))
    end
    for _, itemUnit in ipairs(groundBoxState.itemUnits or {}) do
        appendUniqueUnits(jointUnits, GameAPI.get_joint_assistants(itemUnit))
    end

    groundBoxStates:set(groundBoxState.boxUnit, nil)
    debugLog("destroy collected joints, count:", #jointUnits)
    destroyJointUnits(jointUnits)
    debugLog("destroy ground items, count:", #(groundBoxState.itemUnits or {}))
    destroyUnits(groundBoxState.itemUnits)
    debugLog("destroy ground box unit:", groundBoxState.boxUnit)
    GameAPI.destroy_unit(groundBoxState.boxUnit)
end

---@param roleCtrlUnit Character
---@param followState table
local function reindexFollowLayers(roleCtrlUnit, followState)
    for boxIndex, followLayer in ipairs(followState.boxes) do
        local targetStackIndex = boxIndex - 1
        if followLayer.stackIndex ~= targetStackIndex then
            local newFollowLayer = createFollowLayer(roleCtrlUnit, targetStackIndex)
            if newFollowLayer ~= nil then
                destroyFollowLayer(roleCtrlUnit, followLayer)
                followState.boxes[boxIndex] = newFollowLayer
            else
                print(TAG, "reindex failed, keep old layer:", followLayer.stackIndex, "target:", targetStackIndex)
            end
        end
    end
end

---@param roleCtrlUnit Character|nil
---@param boxUnit Unit|nil
local function pickupGroundBox(roleCtrlUnit, boxUnit)
    if roleCtrlUnit == nil or boxUnit == nil then
        return
    end

    local groundBoxState = groundBoxStates:get(boxUnit)
    if groundBoxState == nil then
        print(TAG, "missing ground box state, boxUnit:", boxUnit)
        return
    end

    local followState = getOrCreateFollowState(roleCtrlUnit)
    local followLayer = createFollowLayer(roleCtrlUnit, #followState.boxes)
    if followLayer == nil then
        clearFollowStateIfEmpty(roleCtrlUnit)
        return
    end

    destroyGroundBoxState(groundBoxState)
    followState.boxes[#followState.boxes + 1] = followLayer
end

---@param roleCtrlUnit Character
---@return Unit|nil
local function spawnGroundBox(roleCtrlUnit)
    local groundBoxState = createGroundBoxState(roleCtrlUnit)
    if groundBoxState == nil then
        return nil
    end
    return groundBoxState.boxUnit
end

---@param role Role|nil
---@return Unit|nil
local function createBoxInFront(role)
    local roleCtrlUnit = getRoleCtrlUnit(role)
    if roleCtrlUnit == nil then
        return nil
    end

    return spawnGroundBox(roleCtrlUnit)
end

---@param boxUnit Unit
local function registerGroundBoxEvents(boxUnit)
    debugLog("register obstacle debug events, boxUnit:", boxUnit)

    LuaAPI.unit_register_trigger_event(boxUnit, { EVENT.SPEC_OBSTACLE_TOUCH_BEGIN }, function(eventName, touchActor, touchData)
        debugLog("obstacle touch begin, event:", eventName, "actor:", touchActor, "data:", touchData)
    end)

    LuaAPI.unit_register_trigger_event(boxUnit, { EVENT.SPEC_OBSTACLE_TOUCH_END }, function(eventName, touchActor, touchData)
        debugLog("obstacle touch end, event:", eventName, "actor:", touchActor, "data:", touchData)
    end)

    LuaAPI.unit_register_trigger_event(boxUnit, { EVENT.SPEC_OBSTACLE_INTERACTED }, function(_, interactActor, interactData)
        debugLog("obstacle interacted callback entered, actor:", interactActor, "data:", interactData)
        if interactData == nil then
            print(TAG, "interact data is nil")
            return
        end

        local interactCtrlUnit = interactData.interact_lifeentity
        if interactCtrlUnit == nil then
            print(TAG, "interact lifeentity is nil, interact unit:", interactData.interact_unit, "interact id:", interactData.interact_id)
            return
        end

        debugLog("interact data fields, ctrlUnit:", interactCtrlUnit, "unit:", interactData.interact_unit, "id:", interactData.interact_id)
        pickupGroundBox(interactCtrlUnit, boxUnit)
    end)
end

---@param role Role|nil
local function releaseLiftBox(role)
    local roleCtrlUnit = getRoleCtrlUnit(role)
    if roleCtrlUnit == nil then
        return
    end

    local followState = roleFollowStates:get(roleCtrlUnit)
    if followState == nil or #followState.boxes == 0 then
        return
    end

    local releasedFollowLayer = followState.boxes[1]

    local releaseBoxUnit = spawnGroundBox(roleCtrlUnit)
    if releaseBoxUnit == nil then
        print(TAG, "create release box failed")
        return
    end

    table.remove(followState.boxes, 1)
    destroyFollowLayer(roleCtrlUnit, releasedFollowLayer)
    registerGroundBoxEvents(releaseBoxUnit)
    reindexFollowLayers(roleCtrlUnit, followState)
    clearFollowStateIfEmpty(roleCtrlUnit)
end

local function cleanupAll()
    debugLog("cleanupAll start")
    for _, boxUnit in ipairs(groundBoxStates:keys()) do
        debugLog("cleanup ground box, boxUnit:", boxUnit)
        destroyGroundBoxState(groundBoxStates:get(boxUnit))
    end

    for _, roleCtrlUnit in ipairs(roleFollowStates:keys()) do
        local followState = roleFollowStates:get(roleCtrlUnit)
        if followState ~= nil then
            debugLog("cleanup follow state, roleCtrlUnit:", roleCtrlUnit, "layerCount:", #followState.boxes)
            for _, followLayer in ipairs(followState.boxes) do
                destroyFollowLayer(roleCtrlUnit, followLayer)
            end
            roleFollowStates:set(roleCtrlUnit, nil)
        end
    end
    debugLog("cleanupAll done")
end

---@param node Node|nil
---@param handler fun(actor: Actor|nil, data: table|nil)
local function registerButton(node, handler)
    if node == nil then
        return false
    end

    LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, node, 1 }, function(_, actor, data)
        if data == nil then
            print(TAG, "touch event data is nil")
            return
        end
        print(TAG, "node touched! actor:", actor)
        print(TAG, "role:", data.role)
        print(TAG, "eui_node_id:", data.eui_node_id)
        handler(actor, data)
    end)
    return true
end

function TestCreateFrontBox.init()
    if not registerButton(UINodes.TestCreateBtn, function(_, data)
        if data == nil then
            return
        end
        local boxUnit = createBoxInFront(data.role)
        print(TAG, "boxUnit:", boxUnit)
        if boxUnit ~= nil then
            GlobalAPI.show_tips("箱子创建成功！", 2.0)
            registerGroundBoxEvents(boxUnit)
        else
            GlobalAPI.show_tips("箱子创建失败！", 2.0)
        end
    end) then
        GlobalAPI.show_tips("missing ui node: TestCreateBtn", 3.0)
        return
    end

    if not registerButton(UINodes.TestReleaseBtn, function(_, data)
        if data == nil then
            return
        end
        releaseLiftBox(data.role)
    end) then
        GlobalAPI.show_tips("missing ui node: TestReleaseBtn", 3.0)
    end

    if not registerButton(UINodes.ClearBtn, function()
        cleanupAll()
        GlobalAPI.show_tips("测试箱子已清理", 2.0)
    end) then
        GlobalAPI.show_tips("missing ui node: ClearBtn", 3.0)
    end
end

return TestCreateFrontBox
