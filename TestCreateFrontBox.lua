local TestCreateFrontBox = {}

local TAG = "[TestCreateFrontBox]"
local Prefab = require("Data.Prefab")
local UINodes = require("Data.UINodes")
local ItemAttConfig = require("Config.ItemAttConfig")

local DEBUG_LOG_ENABLED = false -- 排障日志开关（默认关闭；定位箱子互动链路时再开启）
local TEST_BOX_ID = Prefab.unit.FinalBox -- 箱子模型ID（Prefab.unit）
local DEFAULT_QUATERNION = math.Quaternion(0.0, 0.0, 0.0) -- 默认旋转（DisplayComp.bind_model _rot）
local BOX_SCALE = math.Vector3(1.0, 1.0, 1.0) -- 箱子缩放（DisplayComp.bind_model/create_unit_with_scale _scale）
local BOX_BASE_POINT_OFFSET = math.Vector3(0.0, -0.6, 0.0) -- 箱子原点到底面的修正偏移（位置对齐，单位待确认）
local BOX_TARGET_POSITION_OFFSET = math.Vector3(0.0, 0.0, 0.0) -- 人物前方落点附加偏移（正负方向同世界坐标，单位待确认）
local CREATE_FORWARD_DISTANCE = 2.0 -- 箱子生成人物前方距离（Enums.DirectionType.FORWARD，单位待确认）
local FOLLOW_STACK_HEIGHT_STEP = 3.0 -- 头顶堆叠层高步长（DisplayComp.bind_model _offset.y，单位待确认）
local FOLLOW_SOCKET = Enums.ModelSocket.socket_head -- 绑定挂点（Enums.ModelSocket）
local BOX_LAYER_BASE_OFFSET = math.Vector3(0.0, 1.0, 0.0) -- 第 0 层箱子相对挂点基准偏移（DisplayComp.bind_model _offset，单位待确认）

local groundBoxStates = dict()
local roleFollowStates = dict()

---@alias Node string
---@alias BoxConsumeErrCode "missing_role"|"missing_ctrl_unit"|"no_follow_box"|"follow_box_empty"|"item_type_mismatch"

local function debugLog(...)
    if not DEBUG_LOG_ENABLED then
        return
    end
    print(TAG, ...)
end

---@return table[]|nil
local function buildRuntimeItemAttConfigs()
    local itemAttConfig = ItemAttConfig.getItemAttDefByItemId(nil)
    if itemAttConfig == nil then
        print(TAG, "missing item att defi")
        return nil
    end

    local itemId = itemAttConfig.itemId
    local itemUnitKey = itemAttConfig.itemUnitKey
    local itemScale = itemAttConfig.itemScale
    local itemCount = itemAttConfig.itemCount
    local rowCount = itemAttConfig.rowCount
    local xSpacing = itemAttConfig.xSpacing
    local zSpacing = itemAttConfig.zSpacing
    local yOffset = itemAttConfig.yOffset
    if itemId == nil or itemUnitKey == nil or itemScale == nil or itemCount == nil or rowCount == nil or xSpacing == nil or zSpacing == nil or yOffset == nil then
        print(TAG, "invalid resolved item att defi, itemId:", itemId)
        return nil
    end

    local effectiveRowCount = rowCount
    if itemCount < effectiveRowCount then
        effectiveRowCount = itemCount
    end

    local perRow = (itemCount + effectiveRowCount - 1) // effectiveRowCount

    local runtimeItems = {}
    for slotIndex = 1, itemCount do
        local slotOffset = slotIndex - 1
        local rowIndex = slotOffset // perRow + 1
        local columnIndex = slotOffset % perRow + 1
        local rowX = (columnIndex - (perRow + 1) / 2.0) * xSpacing
        local rowZ = ((effectiveRowCount + 1) / 2.0 - rowIndex) * zSpacing
        runtimeItems[#runtimeItems + 1] = {
            index = slotIndex,
            itemId = itemId,
            itemUnitKey = itemUnitKey,
            itemScale = itemScale,
            localOffset = math.Vector3(rowX, yOffset, rowZ),
        }
    end

    if #runtimeItems ~= itemCount then
        print(
            TAG,
            "item att runtime count mismatch, itemId:",
            itemId,
            "expected:",
            itemCount,
            "actual:",
            #runtimeItems
        )
        return nil
    end

    return runtimeItems
end

---@return table[]|nil
local function getItemAttConfigs()
    return buildRuntimeItemAttConfigs()
end

---@param slot table
---@return table
local function cloneBoxItemSlot(slot)
    return {
        index = slot.index,
        itemId = slot.itemId,
        itemUnitKey = slot.itemUnitKey,
        itemScale = slot.itemScale,
        localOffset = slot.localOffset,
        consumed = slot.consumed == true,
    }
end

---@param boxInventory table
---@return integer
local function findBoxTailCursor(boxInventory)
    if boxInventory == nil or boxInventory.itemSlots == nil then
        return 0
    end

    for slotIndex = #boxInventory.itemSlots, 1, -1 do
        local slot = boxInventory.itemSlots[slotIndex]
        if slot ~= nil and slot.consumed ~= true then
            return slotIndex
        end
    end
    return 0
end

---@return table|nil
local function createDefaultBoxInventory()
    local itemConfigs = getItemAttConfigs()
    if itemConfigs == nil then
        print(TAG, "missing item att configs for default box inventory")
        return nil
    end

    local itemSlots = {}
    for _, itemConfig in ipairs(itemConfigs) do
        itemSlots[#itemSlots + 1] = {
            index = itemConfig.index,
            itemId = itemConfig.itemId,
            itemUnitKey = itemConfig.itemUnitKey,
            itemScale = itemConfig.itemScale,
            localOffset = itemConfig.localOffset,
            consumed = false,
        }
    end

    return {
        itemSlots = itemSlots,
        tailConsumeCursor = #itemSlots,
    }
end

---@param sourceInventory table|nil
---@return table|nil
local function cloneBoxInventory(sourceInventory)
    if sourceInventory == nil then
        return createDefaultBoxInventory()
    end

    local sourceSlots = sourceInventory.itemSlots
    if type(sourceSlots) ~= "table" then
        print(TAG, "invalid box inventory slots, type:", type(sourceSlots))
        return nil
    end

    local itemSlots = {}
    for _, sourceSlot in ipairs(sourceSlots) do
        itemSlots[#itemSlots + 1] = cloneBoxItemSlot(sourceSlot)
    end

    local tailConsumeCursor = findBoxTailCursor({ itemSlots = itemSlots })
    return {
        itemSlots = itemSlots,
        tailConsumeCursor = tailConsumeCursor,
    }
end

---@param boxInventory table
---@return boolean
local function isBoxInventoryEmpty(boxInventory)
    return findBoxTailCursor(boxInventory) <= 0
end

---@param boxInventory table
---@return integer|nil
local function consumeItemSlotFromTail(boxInventory)
    if boxInventory == nil or type(boxInventory.itemSlots) ~= "table" then
        return nil
    end

    local startIndex = boxInventory.tailConsumeCursor
    if type(startIndex) ~= "number" or startIndex < 1 then
        startIndex = #boxInventory.itemSlots
    end
    if startIndex ~= math.floor(startIndex) then
        startIndex = math.floor(startIndex)
    end

    for slotIndex = startIndex, 1, -1 do
        local slot = boxInventory.itemSlots[slotIndex]
        if slot ~= nil and slot.consumed ~= true then
            slot.consumed = true
            boxInventory.tailConsumeCursor = slotIndex - 1
            return slotIndex
        end
    end

    boxInventory.tailConsumeCursor = 0
    return nil
end

---@param boxInventory table
---@return integer|nil
---@return table|nil
local function peekItemSlotFromTail(boxInventory)
    if boxInventory == nil or type(boxInventory.itemSlots) ~= "table" then
        return nil, nil
    end

    local startIndex = boxInventory.tailConsumeCursor
    if type(startIndex) ~= "number" or startIndex < 1 then
        startIndex = #boxInventory.itemSlots
    end
    if startIndex ~= math.floor(startIndex) then
        startIndex = math.floor(startIndex)
    end

    for slotIndex = startIndex, 1, -1 do
        local slot = boxInventory.itemSlots[slotIndex]
        if slot ~= nil and slot.consumed ~= true then
            return slotIndex, slot
        end
    end

    return nil, nil
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
---@return Vector3
local function getLayerBoxOffset(stackIndex)
    return BOX_LAYER_BASE_OFFSET + math.Vector3(0.0, stackIndex * FOLLOW_STACK_HEIGHT_STEP, 0.0)
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
---@param boxInventory table|nil
---@return table|nil
local function createFollowLayer(roleCtrlUnit, stackIndex, boxInventory)
    if boxInventory == nil or type(boxInventory.itemSlots) ~= "table" then
        print(TAG, "invalid box inventory for follow layer")
        return nil
    end

    local boxOffset = getLayerBoxOffset(stackIndex)
    local boxBindId = roleCtrlUnit.bind_model(TEST_BOX_ID, FOLLOW_SOCKET, boxOffset, DEFAULT_QUATERNION, BOX_SCALE)
    if boxBindId == nil then
        print(TAG, "bind box failed at layer:", stackIndex)
        return nil
    end

    local itemBindIds = {}
    local itemBindIdByIndex = {}
    for _, itemSlot in ipairs(boxInventory.itemSlots) do
        if itemSlot.consumed ~= true then
            local runtimeItemIndex = itemSlot.index
            local itemOffset = boxOffset + itemSlot.localOffset
            local itemBindId = roleCtrlUnit.bind_model(
                itemSlot.itemUnitKey,
                FOLLOW_SOCKET,
                itemOffset,
                DEFAULT_QUATERNION,
                itemSlot.itemScale
            )
            if itemBindId == nil then
                unbindModels(roleCtrlUnit, { boxBindId })
                unbindModels(roleCtrlUnit, itemBindIds)
                print(TAG, "bind item failed at layer:", stackIndex, "index:", runtimeItemIndex)
                return nil
            end
            itemBindIds[#itemBindIds + 1] = itemBindId
            itemBindIdByIndex[runtimeItemIndex] = itemBindId
        end
    end

    return {
        boxBindId = boxBindId,
        itemBindIds = itemBindIds,
        itemBindIdByIndex = itemBindIdByIndex,
        inventory = boxInventory,
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
---@param boxInventory table|nil
---@return Unit[]|nil, JointAssistant[]|nil
local function createGroundItems(boxUnit, boxInventory)
    if boxInventory == nil or type(boxInventory.itemSlots) ~= "table" then
        print(TAG, "invalid box inventory for ground items")
        return nil
    end

    local itemOrientation = boxUnit.get_orientation()
    local itemUnits = {}

    for _, itemSlot in ipairs(boxInventory.itemSlots) do
        if itemSlot.consumed ~= true then
            local itemPosition = boxUnit.get_local_offset_position(itemSlot.localOffset)
            local itemUnit = GameAPI.create_unit_with_scale(
                itemSlot.itemUnitKey,
                itemPosition,
                itemOrientation,
                itemSlot.itemScale
            )
            if itemUnit == nil then
                destroyUnits(itemUnits)
                return nil
            end

            -- 禁用重力无效，暂时在编辑器固定设置item的重量为1
            -- local gravityOk, gravityErr = pcall(function()
            --     itemUnit.disable_gravity()
            -- end)
            -- if not gravityOk then
            --     print(TAG, "disable gravity failed, itemId:", itemSlot.itemId, "index:", itemSlot.index, "err:", gravityErr)
            -- end

            itemUnits[#itemUnits + 1] = itemUnit
        end
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
---@param sourceInventory table|nil
---@return table|nil
local function createGroundBoxState(roleCtrlUnit, sourceInventory)
    local boxInventory = cloneBoxInventory(sourceInventory)
    if boxInventory == nil then
        print(TAG, "create box inventory failed")
        return nil
    end

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

    local itemUnits, jointUnits = createGroundItems(boxUnit, boxInventory)
    if itemUnits == nil or jointUnits == nil then
        print(TAG, "create ground items failed")
        GameAPI.destroy_unit(boxUnit)
        return nil
    end

    local groundBoxState = {
        boxUnit = boxUnit,
        itemUnits = itemUnits,
        jointUnits = jointUnits,
        inventory = boxInventory,
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
            local newFollowLayer = createFollowLayer(roleCtrlUnit, targetStackIndex, followLayer.inventory)
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

    local followInventory = cloneBoxInventory(groundBoxState.inventory)
    if followInventory == nil then
        print(TAG, "clone ground inventory failed, boxUnit:", boxUnit)
        return
    end

    local followState = getOrCreateFollowState(roleCtrlUnit)
    local followLayer = createFollowLayer(roleCtrlUnit, #followState.boxes, followInventory)
    if followLayer == nil then
        clearFollowStateIfEmpty(roleCtrlUnit)
        return
    end

    destroyGroundBoxState(groundBoxState)
    followState.boxes[#followState.boxes + 1] = followLayer
end

---@param roleCtrlUnit Character
---@param sourceInventory table|nil
---@return Unit|nil
local function spawnGroundBox(roleCtrlUnit, sourceInventory)
    local groundBoxState = createGroundBoxState(roleCtrlUnit, sourceInventory)
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

    return spawnGroundBox(roleCtrlUnit, nil)
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

---@param roleCtrlUnit Character
---@param followLayer table|nil
---@param itemIndex integer
local function unbindFollowLayerItem(roleCtrlUnit, followLayer, itemIndex)
    if followLayer == nil or followLayer.itemBindIdByIndex == nil then
        return
    end

    local bindId = followLayer.itemBindIdByIndex[itemIndex]
    if bindId == nil then
        return
    end

    followLayer.itemBindIdByIndex[itemIndex] = nil
    pcall(function()
        roleCtrlUnit.unbind_model(bindId)
    end)
end

---@param roleCtrlUnit Character
---@param followLayer table|nil
---@return table|nil
local function consumeFollowLayerTailItem(roleCtrlUnit, followLayer)
    if followLayer == nil or followLayer.inventory == nil then
        return nil
    end

    local slotIndex = consumeItemSlotFromTail(followLayer.inventory)
    if slotIndex == nil then
        return nil
    end

    local itemSlot = followLayer.inventory.itemSlots[slotIndex]
    if itemSlot == nil then
        return nil
    end

    unbindFollowLayerItem(roleCtrlUnit, followLayer, itemSlot.index)
    return {
        itemIndex = itemSlot.index,
        itemId = itemSlot.itemId,
        itemUnitKey = itemSlot.itemUnitKey,
        itemScale = itemSlot.itemScale,
        localOffset = itemSlot.localOffset,
    }
end

---@param role Role|nil
---@param expectedItemId string|nil
---@return table|nil consumedItem
---@return BoxConsumeErrCode|nil errCode
function TestCreateFrontBox.consumeFollowBoxItemByRole(role, expectedItemId)
    if role == nil then
        print(TAG, "consume follow box failed, missing role")
        return nil, "missing_role"
    end

    local roleCtrlUnit = role.get_ctrl_unit()
    if roleCtrlUnit == nil then
        print(TAG, "consume follow box failed, missing ctrl unit")
        return nil, "missing_ctrl_unit"
    end

    local followState = roleFollowStates:get(roleCtrlUnit)
    if followState == nil or #followState.boxes == 0 then
        return nil, "no_follow_box"
    end

    local expectedItemIdValue = nil
    if type(expectedItemId) == "string" and expectedItemId ~= "" then
        expectedItemIdValue = expectedItemId
    end

    for boxIndex = #followState.boxes, 1, -1 do
        local followLayer = followState.boxes[boxIndex]
        if followLayer == nil then
            table.remove(followState.boxes, boxIndex)
            reindexFollowLayers(roleCtrlUnit, followState)
        else
            local _, peekItemSlot = peekItemSlotFromTail(followLayer.inventory)
            if peekItemSlot ~= nil and expectedItemIdValue ~= nil and peekItemSlot.itemId ~= expectedItemIdValue then
                return nil, "item_type_mismatch"
            end

            local consumedItem = consumeFollowLayerTailItem(roleCtrlUnit, followLayer)
            if consumedItem ~= nil then
                if isBoxInventoryEmpty(followLayer.inventory) then
                    table.remove(followState.boxes, boxIndex)
                    destroyFollowLayer(roleCtrlUnit, followLayer)
                    reindexFollowLayers(roleCtrlUnit, followState)
                    clearFollowStateIfEmpty(roleCtrlUnit)
                end
                return consumedItem, nil
            end

            if isBoxInventoryEmpty(followLayer.inventory) then
                table.remove(followState.boxes, boxIndex)
                destroyFollowLayer(roleCtrlUnit, followLayer)
                reindexFollowLayers(roleCtrlUnit, followState)
            end
        end
    end

    clearFollowStateIfEmpty(roleCtrlUnit)
    return nil, "follow_box_empty"
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

    local releasedFollowLayer = followState.boxes[#followState.boxes]

    local releaseBoxUnit = spawnGroundBox(roleCtrlUnit, releasedFollowLayer.inventory)
    if releaseBoxUnit == nil then
        print(TAG, "create release box failed")
        return
    end

    table.remove(followState.boxes, #followState.boxes)
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
