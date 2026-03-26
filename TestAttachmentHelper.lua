local TestAttachmentHelper = {}

local TAG = "[TestAttachmentHelper]"
local Timer = require("Utils.Timer")
local UINodes = require("Data.UINodes")
local Prefab = require("Data.Prefab")
local ShelfAttachmentConfig = require("Config.ShelfAttachmentConfig")
local TestCreateFrontBox = require("TestCreateFrontBox")

local SUCCESS_TIPS_DURATION = 2.0 -- 成功提示时长（GlobalAPI.show_tips _duration，单位：秒）
local ERROR_TIPS_DURATION = 3.0 -- 失败提示时长（GlobalAPI.show_tips _duration，单位：秒）
local DEBUG_LOG_ENABLED = false -- 排障日志开关（默认关闭）
local DEFAULT_SCALE = math.Vector3(1.0, 1.0, 1.0) -- 默认缩放（GameAPI.create_unit_with_scale _scale）
local DEFAULT_ROTATION_OFFSET = math.Quaternion(0.0, 0.0, 0.0) -- 默认旋转偏移（GameAPI.create_unit_with_scale _rotation）
local SHELF_ROW_BUTTON_SIDE_GAP = 2.0 -- 每层按钮相对最右 Attachment 的横向外移（buildLocalOffset 列轴本地偏移，单位：米）
local SHELF_ROW_BUTTON_DURATION = -1.0 -- 每层按钮 SceneUI 持续时长（SceneUI.create_scene_ui_bind_unit _duration，-1 常驻）
local SHELF_ROW_BUTTON_SOCKET = Enums.ModelSocket.socket_body -- 每层按钮 SceneUI 绑定挂点（SceneUI.create_scene_ui_bind_unit _socket_name）
local DEPLOY_BUSY_KV_KEY = "test_attachment_deploy_busy" -- 玩家上架互斥状态键（KVBase.set_kv_by_type/get_kv_by_type）
local DEPLOY_STEP_INTERVAL_SEC = 0.2 -- 自动上架单步间隔（Timer.new duration，单位：秒）

local AXIS_ENUM = {
    x = true,
    y = true,
    z = true,
}

local shelfAttachmentStates = dict()
local shelfDestroyQueue = {}
local roleDeployBusyStates = dict()
local roleDeployTimers = dict()
local inited = false

local function debugLog(...)
    if not DEBUG_LOG_ENABLED then
        return
    end
    print(TAG, ...)
end

---@param value any
---@return boolean
local function isPlatformNumber(value)
    local valueType = type(value)
    return valueType == "number" or valueType == "Fixed"
end

---@param value any
---@return number
local function toRealNumber(value)
    if type(value) == "Fixed" then
        return math.toreal(value)
    end
    return value
end

---@param shelfId string
---@param fieldPath string
---@param value any
local function logShelfFieldError(shelfId, fieldPath, value)
    print(TAG, "invalid shelf config field, shelfId:", shelfId, "field:", fieldPath, "value:", value, "type:", type(value))
end

---@param shelfId string
---@param fieldPath string
---@param value any
---@return number|nil
local function parseNumber(shelfId, fieldPath, value)
    if not isPlatformNumber(value) then
        logShelfFieldError(shelfId, fieldPath, value)
        return nil
    end
    return toRealNumber(value)
end

---@param shelfId string
---@param fieldPath string
---@param value any
---@return integer|nil
local function parsePositiveInteger(shelfId, fieldPath, value)
    if type(value) ~= "number" or value ~= math.floor(value) then
        logShelfFieldError(shelfId, fieldPath, value)
        return nil
    end

    local integerValue = math.tointeger(value)
    if integerValue == nil or integerValue <= 0 then
        logShelfFieldError(shelfId, fieldPath, value)
        return nil
    end

    return integerValue
end

---@param shelfId string
---@param fieldPath string
---@param value any
---@return integer|nil
local function parseUnitKey(shelfId, fieldPath, value)
    return parsePositiveInteger(shelfId, fieldPath, value)
end

---@param shelfId string
---@param fieldPath string
---@param value any
---@return Vector3|nil
local function parseVector3(shelfId, fieldPath, value)
    if type(value) ~= "table" then
        logShelfFieldError(shelfId, fieldPath, value)
        return nil
    end

    local x = parseNumber(shelfId, fieldPath .. ".x", value.x)
    local y = parseNumber(shelfId, fieldPath .. ".y", value.y)
    local z = parseNumber(shelfId, fieldPath .. ".z", value.z)
    if x == nil or y == nil or z == nil then
        return nil
    end

    return math.Vector3(x, y, z)
end

---@param shelfId string
---@param fieldPath string
---@param value any
---@return Quaternion|nil
local function parseEulerDegQuaternion(shelfId, fieldPath, value)
    if type(value) ~= "table" then
        logShelfFieldError(shelfId, fieldPath, value)
        return nil
    end

    local xDeg = parseNumber(shelfId, fieldPath .. ".x", value.x)
    local yDeg = parseNumber(shelfId, fieldPath .. ".y", value.y)
    local zDeg = parseNumber(shelfId, fieldPath .. ".z", value.z)
    if xDeg == nil or yDeg == nil or zDeg == nil then
        return nil
    end

    return math.Quaternion(math.deg_to_rad(xDeg), math.deg_to_rad(yDeg), math.deg_to_rad(zDeg))
end

---@param shelfId string
---@param fieldPath string
---@param value any
---@return "x"|"y"|"z"|nil
local function parseAxisName(shelfId, fieldPath, value)
    if type(value) ~= "string" or not AXIS_ENUM[value] then
        logShelfFieldError(shelfId, fieldPath, value)
        return nil
    end
    return value
end

---@param shelfId string
---@param fieldPath string
---@param value any
---@return integer|nil
local function parseAxisSign(shelfId, fieldPath, value)
    if type(value) ~= "number" or value ~= math.floor(value) then
        logShelfFieldError(shelfId, fieldPath, value)
        return nil
    end

    local sign = math.tointeger(value)
    if sign == nil or (sign ~= 1 and sign ~= -1) then
        logShelfFieldError(shelfId, fieldPath, value)
        return nil
    end

    return sign
end

---@param shelfConfig table
---@return table|nil
local function buildRuntimeShelfConfig(shelfConfig)
    if type(shelfConfig) ~= "table" then
        print(TAG, "shelfConfig must be table, type:", type(shelfConfig))
        return nil
    end

    local shelfId = shelfConfig.shelfId
    if type(shelfId) ~= "string" or shelfId == "" then
        logShelfFieldError("<unknown>", "shelfId", shelfId)
        return nil
    end

    local shelfUnitKey = parseUnitKey(shelfId, "shelfUnitKey", shelfConfig.shelfUnitKey)
    local attachmentUnitKey = parseUnitKey(shelfId, "attachmentUnitKey", shelfConfig.attachmentUnitKey)
    local shelfScale = parseVector3(shelfId, "shelfScale", shelfConfig.shelfScale)
    local attachmentScale = parseVector3(shelfId, "attachmentScale", shelfConfig.attachmentScale)
    local spawnIntervalSec = parseNumber(shelfId, "spawnIntervalSec", shelfConfig.spawnIntervalSec)
    local shelfRotationOffset = parseEulerDegQuaternion(
        shelfId,
        "shelfRotationOffsetEulerDeg",
        shelfConfig.shelfRotationOffsetEulerDeg
    )
    local attachmentRotationOffset = parseEulerDegQuaternion(
        shelfId,
        "attachmentRotationOffsetEulerDeg",
        shelfConfig.attachmentRotationOffsetEulerDeg
    )

    local layout = shelfConfig.layout
    if type(layout) ~= "table" then
        logShelfFieldError(shelfId, "layout", layout)
        return nil
    end

    local rowCount = parsePositiveInteger(shelfId, "layout.rowCount", layout.rowCount)
    local perRow = parsePositiveInteger(shelfId, "layout.perRow", layout.perRow)
    local firstRowHeight = parseNumber(shelfId, "layout.firstRowHeight", layout.firstRowHeight)
    local rowHeightStep = parseNumber(shelfId, "layout.rowHeightStep", layout.rowHeightStep)
    local columnSpacing = parseNumber(shelfId, "layout.columnSpacing", layout.columnSpacing)
    local columnOffset = parseNumber(shelfId, "layout.columnOffset", layout.columnOffset)
    local depthOffset = parseNumber(shelfId, "layout.depthOffset", layout.depthOffset)

    local axisMap = layout.axisMap
    if type(axisMap) ~= "table" then
        logShelfFieldError(shelfId, "layout.axisMap", axisMap)
        return nil
    end

    local columnAxis = parseAxisName(shelfId, "layout.axisMap.columnAxis", axisMap.columnAxis)
    local heightAxis = parseAxisName(shelfId, "layout.axisMap.heightAxis", axisMap.heightAxis)
    local depthAxis = parseAxisName(shelfId, "layout.axisMap.depthAxis", axisMap.depthAxis)
    local columnSign = parseAxisSign(shelfId, "layout.axisMap.columnSign", axisMap.columnSign)
    local heightSign = parseAxisSign(shelfId, "layout.axisMap.heightSign", axisMap.heightSign)
    local depthSign = parseAxisSign(shelfId, "layout.axisMap.depthSign", axisMap.depthSign)

    if shelfUnitKey == nil or attachmentUnitKey == nil or shelfScale == nil or attachmentScale == nil then
        return nil
    end
    if spawnIntervalSec == nil or spawnIntervalSec <= 0.0 then
        logShelfFieldError(shelfId, "spawnIntervalSec", shelfConfig.spawnIntervalSec)
        return nil
    end
    if shelfRotationOffset == nil or attachmentRotationOffset == nil then
        return nil
    end
    if rowCount == nil or perRow == nil then
        return nil
    end
    if firstRowHeight == nil or rowHeightStep == nil or columnSpacing == nil or columnOffset == nil or depthOffset == nil then
        return nil
    end
    if columnAxis == nil or heightAxis == nil or depthAxis == nil then
        return nil
    end
    if columnSign == nil or heightSign == nil or depthSign == nil then
        return nil
    end

    if columnAxis == heightAxis or columnAxis == depthAxis or heightAxis == depthAxis then
        print(TAG, "invalid axis map duplicate axis, shelfConfig:", shelfId, "column:", columnAxis, "height:", heightAxis, "depth:", depthAxis)
        return nil
    end

    return {
        shelfId = shelfId,
        shelfUnitKey = shelfUnitKey,
        attachmentUnitKey = attachmentUnitKey,
        shelfScale = shelfScale,
        attachmentScale = attachmentScale,
        spawnIntervalSec = spawnIntervalSec,
        shelfRotationOffset = shelfRotationOffset,
        attachmentRotationOffset = attachmentRotationOffset,
        layout = {
            rowCount = rowCount,
            perRow = perRow,
            firstRowHeight = firstRowHeight,
            rowHeightStep = rowHeightStep,
            columnSpacing = columnSpacing,
            columnOffset = columnOffset,
            depthOffset = depthOffset,
            axisMap = {
                columnAxis = columnAxis,
                columnSign = columnSign,
                heightAxis = heightAxis,
                heightSign = heightSign,
                depthAxis = depthAxis,
                depthSign = depthSign,
            },
        },
    }
end

---@return number|nil
local function loadCreateForwardDistance()
    local createForwardDistance = ShelfAttachmentConfig.CREATE_FORWARD_DISTANCE
    if not isPlatformNumber(createForwardDistance) then
        print(
            TAG,
            "invalid config field, field: CREATE_FORWARD_DISTANCE",
            "value:",
            createForwardDistance,
            "type:",
            type(createForwardDistance)
        )
        return nil
    end

    local forwardDistance = toRealNumber(createForwardDistance)
    if forwardDistance <= 0.0 then
        print(
            TAG,
            "invalid config field, field: CREATE_FORWARD_DISTANCE",
            "value:",
            createForwardDistance,
            "type:",
            type(createForwardDistance)
        )
        return nil
    end

    return forwardDistance
end

---@return boolean|nil
local function loadEnableSlowSpawn()
    local enableSlowSpawn = ShelfAttachmentConfig.ENABLE_SLOW_SPAWN
    if type(enableSlowSpawn) ~= "boolean" then
        print(
            TAG,
            "invalid config field, field: ENABLE_SLOW_SPAWN",
            "value:",
            enableSlowSpawn,
            "type:",
            type(enableSlowSpawn)
        )
        return nil
    end

    return enableSlowSpawn
end

---@return boolean|nil
local function loadDeployTouchUseSuffix()
    local deployTouchUseSuffix = ShelfAttachmentConfig.DEPLOY_TOUCH_USE_SUFFIX
    if type(deployTouchUseSuffix) ~= "boolean" then
        print(
            TAG,
            "invalid config field, field: DEPLOY_TOUCH_USE_SUFFIX",
            "value:",
            deployTouchUseSuffix,
            "type:",
            type(deployTouchUseSuffix)
        )
        return nil
    end

    return deployTouchUseSuffix
end

---@param shelfId string|nil
---@return table|nil
---@return string|nil
local function resolveRuntimeShelfConfig(shelfId)
    local shelfConfig = ShelfAttachmentConfig.get_shelf_config_by_id(shelfId)
    if shelfConfig == nil then
        return nil, "missing"
    end

    local runtimeShelfConfig = buildRuntimeShelfConfig(shelfConfig)
    if runtimeShelfConfig == nil then
        return nil, "invalid"
    end

    return runtimeShelfConfig, nil
end

---@param role Role|nil
---@param unitKey UnitKey
---@param unitName string
---@param scale Vector3|nil
---@param rotationOffset Quaternion|nil
---@param createForwardDistance number
---@return Unit|nil
local function createUnitInFront(role, unitKey, unitName, scale, rotationOffset, createForwardDistance)
    if scale == nil then
        scale = DEFAULT_SCALE
    end
    if rotationOffset == nil then
        rotationOffset = DEFAULT_ROTATION_OFFSET
    end

    if role == nil then
        print(TAG, "missing role for create:", unitName)
        GlobalAPI.show_tips("角色信息缺失，创建失败", ERROR_TIPS_DURATION)
        return nil
    end

    local ctrlUnit = role.get_ctrl_unit()
    if ctrlUnit == nil then
        print(TAG, "missing ctrl unit for create:", unitName)
        GlobalAPI.show_tips("角色控制单位缺失，创建失败", ERROR_TIPS_DURATION)
        return nil
    end

    local spawnPosition = ctrlUnit.get_position()
        + ctrlUnit.get_local_direction(Enums.DirectionType.FORWARD) * createForwardDistance
    local spawnRotation = ctrlUnit.get_orientation() * rotationOffset
    local createdUnit = GameAPI.create_unit_with_scale(unitKey, spawnPosition, spawnRotation, scale)
    if createdUnit == nil then
        print(TAG, "create failed:", unitName)
        GlobalAPI.show_tips(unitName .. "创建失败", ERROR_TIPS_DURATION)
        return nil
    end

    print(TAG, "create success:", unitName, createdUnit)
    GlobalAPI.show_tips(unitName .. "创建成功", SUCCESS_TIPS_DURATION)
    return createdUnit
end

---@param shelfConfig table
---@param rowIndex integer
---@param columnIndex integer
---@return Vector3
local function buildLocalOffset(shelfConfig, rowIndex, columnIndex)
    local layout = shelfConfig.layout
    local axisMap = layout.axisMap
    local columnCenterIndex = (layout.perRow + 1) / 2.0

    local columnValue = (columnIndex - columnCenterIndex) * layout.columnSpacing + layout.columnOffset
    local heightValue = layout.firstRowHeight + (rowIndex - 1) * layout.rowHeightStep
    local depthValue = layout.depthOffset

    local components = {
        x = 0.0,
        y = 0.0,
        z = 0.0,
    }

    components[axisMap.columnAxis] = columnValue * axisMap.columnSign
    components[axisMap.heightAxis] = heightValue * axisMap.heightSign
    components[axisMap.depthAxis] = depthValue * axisMap.depthSign

    return math.Vector3(components.x, components.y, components.z)
end

---@param shelfConfig table
---@param rowIndex integer
---@return Vector3
local function buildRowButtonOffset(shelfConfig, rowIndex)
    local layout = shelfConfig.layout
    local axisMap = layout.axisMap
    local rowRightAttachmentOffset = buildLocalOffset(shelfConfig, rowIndex, layout.perRow)
    local rowButtonGapOffset = {
        x = 0.0,
        y = 0.0,
        z = 0.0,
    }
    rowButtonGapOffset[axisMap.columnAxis] = SHELF_ROW_BUTTON_SIDE_GAP * axisMap.columnSign
    return rowRightAttachmentOffset + math.Vector3(rowButtonGapOffset.x, rowButtonGapOffset.y, rowButtonGapOffset.z)
end

---@param shelfUnit Unit
---@param rowButtonLocalOffset Vector3
---@return Vector3
local function buildRowButtonWorldOffset(shelfUnit, rowButtonLocalOffset)
    local rowButtonWorldPosition = shelfUnit.get_local_offset_position(rowButtonLocalOffset)
    local shelfWorldPosition = shelfUnit.get_position()
    return rowButtonWorldPosition - shelfWorldPosition
end

---@param nodeId ENode|string
---@return string
local function normalizeDeployNodeIdForMatch(nodeId)
    -- 引擎回调里的 nodeToken 可能省略前缀（如 1519736575|1448814052 -> 1448814052），这里统一归一化以保证映射可命中。
    local rawNodeId = tostring(nodeId)
    local uiType, sceneUiId, nodeToken = string.match(rawNodeId, "^([^@]+)@([^@]+)@(.+)$")
    if uiType == nil or sceneUiId == nil or nodeToken == nil then
        return rawNodeId
    end

    local normalizedNodeToken = nodeToken
    local separatorIndex = string.find(nodeToken, "|", 1, true)
    if separatorIndex ~= nil and separatorIndex < #nodeToken then
        normalizedNodeToken = string.sub(nodeToken, separatorIndex + 1)
    end

    return uiType .. "@" .. sceneUiId .. "@" .. normalizedNodeToken
end

---@param nodeId ENode|string|nil
---@return string|nil
local function extractNodeIdSuffix(nodeId)
    if type(nodeId) ~= "string" or nodeId == "" then
        return nil
    end

    local separatorIndex = string.find(nodeId, "|", 1, true)
    if separatorIndex == nil or separatorIndex >= #nodeId then
        return nil
    end

    return string.sub(nodeId, separatorIndex + 1)
end

---@param state table
---@param rowIndex integer
---@return integer|nil
local function getNextDeployLayerIndex(state, rowIndex)
    local nextDeployLayerByRow = state.nextDeployLayerByRow
    if nextDeployLayerByRow == nil then
        return nil
    end

    local nextLayerIndex = nextDeployLayerByRow[rowIndex]
    if type(nextLayerIndex) ~= "number" or nextLayerIndex ~= math.floor(nextLayerIndex) then
        return nil
    end
    if nextLayerIndex < 1 then
        return nil
    end
    return math.tointeger(nextLayerIndex)
end

---@param state table
---@param rowIndex integer
---@param layerIndex integer
local function markShelfRowLayerOccupied(state, rowIndex, layerIndex)
    state.nextDeployLayerByRow[rowIndex] = layerIndex + 1

    local rowLayers = state.layers[rowIndex]
    if rowLayers == nil then
        rowLayers = {}
        state.layers[rowIndex] = rowLayers
    end

    local attachmentInfo = rowLayers[layerIndex]
    if attachmentInfo == nil then
        attachmentInfo = {
            rowIndex = rowIndex,
            layerIndex = layerIndex,
            columnIndex = layerIndex,
            anchorUnit = nil,
            deployedItemUnit = nil,
            occupied = false,
        }
        rowLayers[layerIndex] = attachmentInfo
    end

    attachmentInfo.occupied = true
end

---@param role Role|nil
---@return Character|nil
local function getRoleCtrlUnitForDeploy(role)
    if role == nil then
        return nil
    end

    return role.get_ctrl_unit()
end

---@param roleCtrlUnit Character|nil
---@param busy boolean
local function setRoleDeployBusyState(roleCtrlUnit, busy)
    if roleCtrlUnit == nil then
        return
    end

    local busyState = busy == true
    roleDeployBusyStates:set(roleCtrlUnit, busyState)
    pcall(function()
        roleCtrlUnit.set_kv_by_type(Enums.ValueType.Bool, DEPLOY_BUSY_KV_KEY, busyState)
    end)
end

---@param roleCtrlUnit Character|nil
---@return boolean
local function isRoleDeployBusy(roleCtrlUnit)
    if roleCtrlUnit == nil then
        return false
    end

    if roleDeployBusyStates:get(roleCtrlUnit) == true then
        return true
    end

    local kvBusy = false
    local kvReadOk = pcall(function()
        kvBusy = roleCtrlUnit.get_kv_by_type(Enums.ValueType.Bool, DEPLOY_BUSY_KV_KEY) == true
    end)
    return kvReadOk and kvBusy
end

---@param roleCtrlUnit Character|nil
local function clearRoleDeployTimer(roleCtrlUnit)
    if roleCtrlUnit == nil then
        return
    end

    local runningTimer = roleDeployTimers:get(roleCtrlUnit)
    if runningTimer ~= nil then
        runningTimer:cancel()
    end
    roleDeployTimers:set(roleCtrlUnit, nil)
end

---@param role Role|nil
---@return table|nil
local function consumeItemForDeploy(role)
    local consumedItem, errCode = TestCreateFrontBox.consumeFollowBoxItemByRole(role)
    if consumedItem ~= nil then
        return consumedItem
    end

    if errCode == "missing_role" or errCode == "missing_ctrl_unit" then
        GlobalAPI.show_tips("角色信息缺失，无法上架", ERROR_TIPS_DURATION)
    elseif errCode == "no_follow_box" or errCode == "follow_box_empty" then
        GlobalAPI.show_tips("无可用箱子货物", ERROR_TIPS_DURATION)
    else
        GlobalAPI.show_tips("箱子货物扣减失败", ERROR_TIPS_DURATION)
    end
    return nil
end

---@param state table
---@param rowIndex integer
---@param layerIndex integer
---@param consumedItem table
---@return boolean
local function deployItemToTargetLayer(state, rowIndex, layerIndex, consumedItem)
    markShelfRowLayerOccupied(state, rowIndex, layerIndex)
    local rowLayers = state.layers[rowIndex]
    local attachmentInfo = nil
    if rowLayers ~= nil then
        attachmentInfo = rowLayers[layerIndex]
    end

    if attachmentInfo == nil or attachmentInfo.anchorUnit == nil then
        print(
            TAG,
            "missing deploy anchor, shelfId:",
            state.shelfId,
            "rowIndex:",
            rowIndex,
            "layerIndex:",
            layerIndex,
            "itemIndex:",
            consumedItem.itemIndex
        )
        return false
    end

    local deployedItemUnit = GameAPI.create_unit_with_scale(
        consumedItem.itemUnitKey,
        attachmentInfo.anchorUnit.get_position(),
        attachmentInfo.anchorUnit.get_orientation(),
        consumedItem.itemScale
    )
    if deployedItemUnit == nil then
        print(
            TAG,
            "deploy item create failed, shelfId:",
            state.shelfId,
            "rowIndex:",
            rowIndex,
            "layerIndex:",
            layerIndex,
            "itemIndex:",
            consumedItem.itemIndex
        )
        return false
    end

    local physicsOk, physicsErr = pcall(function()
        deployedItemUnit.set_physics_active(false)
    end)
    if not physicsOk then
        print(
            TAG,
            "deploy item disable physics failed, shelfId:",
            state.shelfId,
            "rowIndex:",
            rowIndex,
            "layerIndex:",
            layerIndex,
            "itemIndex:",
            consumedItem.itemIndex,
            "err:",
            physicsErr
        )
    end

    attachmentInfo.deployedItemUnit = deployedItemUnit
    attachmentInfo.deployedItemIndex = consumedItem.itemIndex
    return true
end

---@param state table
---@param rowIndex integer
---@param role Role
---@param roleCtrlUnit Character
---@param rawNodeKey string
---@param normalizedNodeKey string
---@param matchedBy string
---@param onFinished fun(errText: string|nil)
local function autoDeployShelfRow(state, rowIndex, role, roleCtrlUnit, rawNodeKey, normalizedNodeKey, matchedBy, onFinished)
    local startLayerIndex = getNextDeployLayerIndex(state, rowIndex)
    if startLayerIndex == nil then
        print(TAG, "invalid next layer index, shelfId:", state.shelfId, "rowIndex:", rowIndex)
        GlobalAPI.show_tips("货架层索引异常", ERROR_TIPS_DURATION)
        onFinished(nil)
        return
    end
    if startLayerIndex > state.layoutPerRow then
        GlobalAPI.show_tips("该层已上满", ERROR_TIPS_DURATION)
        onFinished(nil)
        return
    end

    local successCount = 0
    local failedCount = 0
    local finished = false
    local deployTimer = Timer.new(DEPLOY_STEP_INTERVAL_SEC, true)
    roleDeployTimers:set(roleCtrlUnit, deployTimer)

    ---@param errText string|nil
    local function finishDeploy(errText)
        if finished then
            return
        end
        finished = true
        clearRoleDeployTimer(roleCtrlUnit)

        if errText ~= nil then
            onFinished(errText)
            return
        end

        if successCount > 0 then
            GlobalAPI.show_tips("自动上架完成，数量: " .. tostring(successCount), SUCCESS_TIPS_DURATION)
        elseif failedCount > 0 then
            GlobalAPI.show_tips("自动上架失败，已占位: " .. tostring(failedCount), ERROR_TIPS_DURATION)
        end
        onFinished(nil)
    end

    deployTimer:setTimeEndCb(function()
        local ok, err = pcall(function()
            if state.destroyed then
                finishDeploy(nil)
                return
            end

            local targetLayerIndex = getNextDeployLayerIndex(state, rowIndex)
            if targetLayerIndex == nil then
                print(TAG, "invalid loop layer index, shelfId:", state.shelfId, "rowIndex:", rowIndex)
                finishDeploy(nil)
                return
            end
            if targetLayerIndex > state.layoutPerRow then
                finishDeploy(nil)
                return
            end

            local consumedItem = consumeItemForDeploy(role)
            if consumedItem == nil then
                finishDeploy(nil)
                return
            end

            local deployed = deployItemToTargetLayer(state, rowIndex, targetLayerIndex, consumedItem)
            if deployed then
                successCount = successCount + 1
                print(
                    TAG,
                    "deploy success, shelfId:",
                    state.shelfId,
                    "rowIndex:",
                    rowIndex,
                    "layerIndex:",
                    targetLayerIndex,
                    "itemIndex:",
                    consumedItem.itemIndex,
                    "rawNodeId:",
                    rawNodeKey,
                    "normalizedNodeId:",
                    normalizedNodeKey,
                    "matchedBy:",
                    matchedBy
                )
            else
                failedCount = failedCount + 1
            end
        end)
        if not ok then
            local errText = tostring(err)
            print(TAG, "auto deploy tick crashed, shelfId:", state.shelfId, "rowIndex:", rowIndex, "err:", errText)
            finishDeploy(errText)
        end
    end)
    deployTimer:start()
end

---@param state table
---@param rowIndex integer
---@param actor Actor|nil
---@param data table|nil
---@param rawNodeKey string
---@param normalizedNodeKey string
---@param matchedBy string
local function handleShelfRowDeployTouch(state, rowIndex, actor, data, rawNodeKey, normalizedNodeKey, matchedBy)
    if data == nil then
        print(TAG, "deploy touch data nil, shelfId:", state.shelfId, "rowIndex:", rowIndex, "actor:", actor)
        return
    end
    if state.destroyed then
        return
    end

    local role = data.role
    if role == nil then
        print(TAG, "deploy touch missing role, shelfId:", state.shelfId, "rowIndex:", rowIndex, "actor:", actor)
        GlobalAPI.show_tips("角色信息缺失，无法上架", ERROR_TIPS_DURATION)
        return
    end

    local roleCtrlUnit = getRoleCtrlUnitForDeploy(role)
    if roleCtrlUnit == nil then
        print(TAG, "deploy touch missing role ctrl unit, shelfId:", state.shelfId, "rowIndex:", rowIndex, "actor:", actor)
        GlobalAPI.show_tips("角色控制单位缺失，无法上架", ERROR_TIPS_DURATION)
        return
    end

    if isRoleDeployBusy(roleCtrlUnit) then
        GlobalAPI.show_tips("上架进行中，请稍后", ERROR_TIPS_DURATION)
        return
    end

    clearRoleDeployTimer(roleCtrlUnit)
    setRoleDeployBusyState(roleCtrlUnit, true)
    local ok, err = pcall(function()
        autoDeployShelfRow(
            state,
            rowIndex,
            role,
            roleCtrlUnit,
            rawNodeKey,
            normalizedNodeKey,
            matchedBy,
            function(deployErr)
                setRoleDeployBusyState(roleCtrlUnit, false)
                if deployErr ~= nil then
                    GlobalAPI.show_tips("自动上架异常", ERROR_TIPS_DURATION)
                end
            end
        )
    end)

    if not ok then
        setRoleDeployBusyState(roleCtrlUnit, false)
        print(TAG, "auto deploy crashed, shelfId:", state.shelfId, "rowIndex:", rowIndex, "err:", err)
        GlobalAPI.show_tips("自动上架异常", ERROR_TIPS_DURATION)
    end
end

---@param state table
---@param sceneUiLayer E3DLayer
---@param rowIndex integer
local function registerShelfRowDeployButton(state, sceneUiLayer, rowIndex)
    local deployBtnNodeId = UINodes.DeployBtn
    if deployBtnNodeId == nil then
        print(TAG, "missing ui node: DeployBtn, shelfId:", state.shelfId, "row:", rowIndex)
        return
    end

    local deployBtnNode = GameAPI.get_eui_node_at_scene_ui(sceneUiLayer, deployBtnNodeId)
    if deployBtnNode == nil then
        print(TAG, "missing scene ui node: DeployBtn, shelfId:", state.shelfId, "row:", rowIndex)
        return
    end

    if state.deployBtnRowByNodeId == nil then
        state.deployBtnRowByNodeId = {}
    end

    local exactNodeKey = tostring(deployBtnNode)
    local normalizedNodeKey = normalizeDeployNodeIdForMatch(deployBtnNode)
    -- 同时保存 exact + normalized，回调先 exact 再 normalized，兼容不同来源的 nodeId 形态。
    state.deployBtnRowByNodeId[exactNodeKey] = rowIndex
    state.deployBtnRowByNodeId[normalizedNodeKey] = rowIndex
    print(
        TAG,
        "register deploy button mapping, shelfId:",
        state.shelfId,
        "rowIndex:",
        rowIndex,
        "exactNodeId:",
        exactNodeKey,
        "normalizedNodeId:",
        normalizedNodeKey
    )
end

---@param state table
---@param sceneUiLayer E3DLayer
---@param rowIndex integer
---@param deployBtnNodeSuffix string
---@return boolean
local function registerShelfRowDeployTouchBySuffix(state, sceneUiLayer, rowIndex, deployBtnNodeSuffix)
    local deployBtnNode = GameAPI.get_eui_node_at_scene_ui(sceneUiLayer, deployBtnNodeSuffix)
    if deployBtnNode == nil then
        print(
            TAG,
            "missing scene ui node by suffix, shelfId:",
            state.shelfId,
            "row:",
            rowIndex,
            "suffix:",
            deployBtnNodeSuffix
        )
        return false
    end

    local triggerId = LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, deployBtnNode, 1 }, function(_, actor, data)
        local rawNodeKey = tostring(deployBtnNode)
        if data ~= nil and data.eui_node_id ~= nil then
            rawNodeKey = tostring(data.eui_node_id)
        end
        handleShelfRowDeployTouch(state, rowIndex, actor, data, rawNodeKey, rawNodeKey, "suffix")
    end)
    if type(triggerId) ~= "number" or triggerId ~= math.floor(triggerId) then
        print(
            TAG,
            "register deploy touch by suffix failed, shelfId:",
            state.shelfId,
            "rowIndex:",
            rowIndex,
            "suffix:",
            deployBtnNodeSuffix,
            "nodeId:",
            tostring(deployBtnNode),
            "triggerId:",
            triggerId
        )
        return false
    end
    state.deployTouchTriggerIdsByRow[rowIndex] = triggerId
    print(
        TAG,
        "register deploy touch by suffix, shelfId:",
        state.shelfId,
        "rowIndex:",
        rowIndex,
        "suffix:",
        deployBtnNodeSuffix,
        "nodeId:",
        tostring(deployBtnNode),
        "triggerId:",
        triggerId
    )
    return true
end

---@param state table|nil
local function destroyShelfRowButtons(state)
    if state == nil then
        return
    end

    for _, triggerId in pairs(state.deployTouchTriggerIdsByRow or {}) do
        if type(triggerId) == "number" and triggerId == math.floor(triggerId) then
            pcall(function()
                LuaAPI.global_unregister_trigger_event(triggerId)
            end)
        end
    end

    for _, sceneUiLayer in pairs(state.sceneUiLayersByRow or {}) do
        if sceneUiLayer ~= nil then
            pcall(function()
                GameAPI.destroy_scene_ui(sceneUiLayer)
            end)
        end
    end
    state.deployTouchTriggerIdsByRow = {}
    state.sceneUiLayersByRow = {}
    state.deployBtnRowByNodeId = {}
    state.deployBtnWarnedUnknownNodeById = {}
end

---@param shelfUnit Unit
---@param shelfConfig table
---@param state table
local function createShelfRowButtons(shelfUnit, shelfConfig, state)
    local layout = shelfConfig.layout
    destroyShelfRowButtons(state)
    state.deployBtnRowByNodeId = {}
    state.deployBtnWarnedUnknownNodeById = {}
    state.deployTouchTriggerIdsByRow = {}

    local deployBtnNodeId = UINodes.DeployBtn
    local deployBtnNodeSuffix = nil
    local suffixFallbackTriggered = false
    -- 回退触发条件 1：配置显式关闭 suffix 触摸注册（DEPLOY_TOUCH_USE_SUFFIX=false）。
    local useSuffixTouch = state.deployTouchUseSuffix == true
    if useSuffixTouch then
        deployBtnNodeSuffix = extractNodeIdSuffix(deployBtnNodeId)
        if deployBtnNodeSuffix == nil then
            -- 回退触发条件 2：DeployBtn 节点不满足 "前缀|后缀" 格式，无法解析后半截 token。
            useSuffixTouch = false
            print(TAG, "invalid DeployBtn node id for suffix mode, fallback to custom event, nodeId:", deployBtnNodeId)
        end
    end

    for rowIndex = 1, layout.rowCount do
        local rowButtonLocalOffset = buildRowButtonOffset(shelfConfig, rowIndex)
        local rowButtonWorldOffset = buildRowButtonWorldOffset(shelfUnit, rowButtonLocalOffset)
        ---@cast shelfUnit Obstacle
        local sceneUiLayer = shelfUnit.create_scene_ui_bind_unit(
            Prefab.scene_eui.DeploySceneUI,
            SHELF_ROW_BUTTON_SOCKET,
            rowButtonWorldOffset,
            SHELF_ROW_BUTTON_DURATION,
            true
        )
        if sceneUiLayer ~= nil then
            state.sceneUiLayersByRow[rowIndex] = sceneUiLayer
            if useSuffixTouch and deployBtnNodeSuffix ~= nil then
                local registerOk = registerShelfRowDeployTouchBySuffix(state, sceneUiLayer, rowIndex, deployBtnNodeSuffix)
                if not registerOk then
                    -- 回退触发条件 3：suffix 触摸注册任一层失败，当前货架整体验证失败，统一切回旧链路。
                    useSuffixTouch = false
                    suffixFallbackTriggered = true
                end
            end

            if not useSuffixTouch then
                if not suffixFallbackTriggered then
                    registerShelfRowDeployButton(state, sceneUiLayer, rowIndex)
                else
                    -- 已触发整货架降级，旧映射将在循环结束后统一重建，避免重复注册。
                end
            else
                -- 当前层已走 suffix 注册，跳过旧映射注册。
            end
        else
            print(TAG, "create shelf row button scene ui failed, shelfId:", state.shelfId, "row:", rowIndex)
        end
    end

    if useSuffixTouch then
        -- suffix 模式生效：已通过 EUI_NODE_TOUCH_EVENT 完成逐层注册，不再注册 DeployBtnClicked 回退链路。
        return
    end

    if suffixFallbackTriggered then
        for _, triggerId in pairs(state.deployTouchTriggerIdsByRow or {}) do
            if type(triggerId) == "number" and triggerId == math.floor(triggerId) then
                pcall(function()
                    LuaAPI.global_unregister_trigger_event(triggerId)
                end)
            end
        end
        state.deployTouchTriggerIdsByRow = {}
        state.deployBtnRowByNodeId = {}
        state.deployBtnWarnedUnknownNodeById = {}
        -- 整货架回退：统一按旧映射链路重建所有已创建层，避免出现“部分 suffix + 部分旧模式”的混合状态。
        for rowIndex = 1, layout.rowCount do
            local sceneUiLayer = state.sceneUiLayersByRow[rowIndex]
            if sceneUiLayer ~= nil then
                registerShelfRowDeployButton(state, sceneUiLayer, rowIndex)
            end
        end
    end

    if state.deployBtnCustomEventRegistered then
        return
    end
    state.deployBtnCustomEventRegistered = true

    -- 回退模式：沿用 SceneUI 编辑器硬编码的 "DeployBtnClicked" 自定义事件。
    -- 事件回调里通过 nodeId 映射到行索引，兼容不同来源的 nodeId 形态（如引擎回调可能省略前缀）。
    LuaAPI.unit_register_custom_event(shelfUnit, "DeployBtnClicked", function(_, actor, data)
        if data == nil then
            print(TAG, "DeployBtnClicked data nil, shelfId:", state.shelfId, "actor:", actor)
            return
        end
        if state.destroyed or shelfAttachmentStates:get(shelfUnit) ~= state then
            return
        end

        local nodeId = data.eui_node_id
        if nodeId == nil then
            print(TAG, "DeployBtnClicked missing eui_node_id, shelfId:", state.shelfId, "actor:", actor)
            return
        end

        local rawNodeKey = tostring(nodeId)
        local normalizedNodeKey = normalizeDeployNodeIdForMatch(nodeId)
        local rowIndex = state.deployBtnRowByNodeId[rawNodeKey]
        local matchedBy = "exact"
        if rowIndex == nil then
            rowIndex = state.deployBtnRowByNodeId[normalizedNodeKey]
            matchedBy = "normalized"
        end

        if rowIndex == nil then
            if state.deployBtnWarnedUnknownNodeById[normalizedNodeKey] ~= true then
                state.deployBtnWarnedUnknownNodeById[normalizedNodeKey] = true
                print(
                    TAG,
                    "DeployBtnClicked unknown node, shelfId:",
                    state.shelfId,
                    "rawNodeId:",
                    rawNodeKey,
                    "normalizedNodeId:",
                    normalizedNodeKey,
                    "actor:",
                    actor
                )
            end
            return
        end

        handleShelfRowDeployTouch(state, rowIndex, actor, data, rawNodeKey, normalizedNodeKey, matchedBy)
    end)
end

---@param shelfConfig table
---@param shelfUnit Unit
---@return Quaternion
local function buildAttachmentRotation(shelfConfig, shelfUnit)
    return shelfUnit.get_orientation() * shelfConfig.attachmentRotationOffset
end

---@param shelfConfig table
---@return table
local function buildAttachmentSpawnTasks(shelfConfig)
    local tasks = {}
    local layout = shelfConfig.layout
    for rowIndex = 1, layout.rowCount do
        for columnIndex = 1, layout.perRow do
            tasks[#tasks + 1] = {
                rowIndex = rowIndex,
                columnIndex = columnIndex,
                layerIndex = columnIndex,
            }
        end
    end
    return tasks
end

---@param shelfUnit Unit
local function enqueueShelfForDestroy(shelfUnit)
    shelfDestroyQueue[#shelfDestroyQueue + 1] = shelfUnit
end

---@param shelfUnit Unit
local function removeShelfFromDestroyQueue(shelfUnit)
    for index, queuedShelfUnit in ipairs(shelfDestroyQueue) do
        if queuedShelfUnit == shelfUnit then
            table.remove(shelfDestroyQueue, index)
            return true
        end
    end
    return false
end

---@return Unit|nil
local function popNextShelfToDestroy()
    if #shelfDestroyQueue == 0 then
        return nil
    end
    local shelfUnit = shelfDestroyQueue[1]
    table.remove(shelfDestroyQueue, 1)
    return shelfUnit
end

---@param state table
local function destroyAttachmentsInState(state)
    for _, rowLayers in pairs(state.layers or {}) do
        for _, attachmentInfo in pairs(rowLayers or {}) do
            local deployedItemUnit = attachmentInfo.deployedItemUnit
            if deployedItemUnit ~= nil then
                pcall(function()
                    GameAPI.destroy_unit(deployedItemUnit)
                end)
            end

            local anchorUnit = attachmentInfo.anchorUnit
            if anchorUnit ~= nil then
                pcall(function()
                    GameAPI.destroy_unit(anchorUnit)
                end)
            end
        end
    end
end

---@param shelfUnit Unit
---@param state table|nil
---@param destroyAttachments boolean|nil
local function clearShelfAttachmentState(shelfUnit, state, destroyAttachments)
    local currentState = shelfAttachmentStates:get(shelfUnit)
    if state == nil then
        state = currentState
    end
    if state == nil then
        return
    end

    state.destroyed = true
    if state.timer ~= nil then
        state.timer:cancel()
        state.timer = nil
    end
    destroyShelfRowButtons(state)
    if destroyAttachments then
        destroyAttachmentsInState(state)
    end
    if currentState == state then
        shelfAttachmentStates:set(shelfUnit, nil)
    end
end

---@param shelfUnit Unit
---@param state table
---@param reason string
local function abortShelfSpawn(shelfUnit, state, reason)
    print(
        TAG,
        "abort shelf attachments, shelfId:",
        state.shelfId,
        "reason:",
        reason,
        "success:",
        state.spawnedCount,
        "failed:",
        state.failedCount
    )
    removeShelfFromDestroyQueue(shelfUnit)
    clearShelfAttachmentState(shelfUnit, state, true)
end

---@param shelfUnit Unit
---@param state table
local function registerShelfDestroyEvents(shelfUnit, state)
    LuaAPI.unit_register_trigger_event(shelfUnit, { EVENT.SPEC_OBSTACLE_DESTROY }, function()
        local currentState = shelfAttachmentStates:get(shelfUnit)
        if currentState == state and not state.destroyed then
            abortShelfSpawn(shelfUnit, state, "SPEC_OBSTACLE_DESTROY")
        end
    end)

    LuaAPI.unit_register_trigger_event(shelfUnit, { EVENT.SPEC_LIFEENTITY_DESTROY }, function()
        local currentState = shelfAttachmentStates:get(shelfUnit)
        if currentState == state and not state.destroyed then
            abortShelfSpawn(shelfUnit, state, "SPEC_LIFEENTITY_DESTROY")
        end
    end)
end

---@param shelfUnit Unit
---@param shelfId string
---@param totalCount integer
---@param rowCount integer
---@param perRow integer
---@param deployTouchUseSuffix boolean
---@return table
local function createShelfAttachmentState(shelfUnit, shelfId, totalCount, rowCount, perRow, deployTouchUseSuffix)
    local oldState = shelfAttachmentStates:get(shelfUnit)
    if oldState ~= nil then
        clearShelfAttachmentState(shelfUnit, oldState, false)
    end

    local nextDeployLayerByRow = {}
    for rowIndex = 1, rowCount do
        nextDeployLayerByRow[rowIndex] = 1
    end

    local state = {
        shelfId = shelfId,
        totalCount = totalCount,
        layoutRowCount = rowCount,
        layoutPerRow = perRow,
        spawnedCount = 0,
        failedCount = 0,
        timer = nil,
        layers = {},
        nextDeployLayerByRow = nextDeployLayerByRow,
        deployTouchUseSuffix = deployTouchUseSuffix == true,
        deployTouchTriggerIdsByRow = {},
        sceneUiLayersByRow = {},
        deployBtnRowByNodeId = {},
        deployBtnWarnedUnknownNodeById = {},
        deployBtnCustomEventRegistered = false,
        destroyed = false,
    }
    shelfAttachmentStates:set(shelfUnit, state)
    return state
end

---@param state table
---@param task table
---@param attachmentUnit Unit
local function recordAttachmentIndex(state, task, attachmentUnit)
    local rowLayers = state.layers[task.rowIndex]
    if rowLayers == nil then
        rowLayers = {}
        state.layers[task.rowIndex] = rowLayers
    end

    rowLayers[task.layerIndex] = {
        anchorUnit = attachmentUnit,
        deployedItemUnit = nil,
        deployedItemIndex = nil,
        occupied = false,
        rowIndex = task.rowIndex,
        columnIndex = task.columnIndex,
        layerIndex = task.layerIndex,
    }
end

---@param shelfUnit Unit
---@param shelfConfig table
---@param state table
---@param task table
local function spawnSingleAttachment(shelfUnit, shelfConfig, state, task)
    if state.destroyed or shelfAttachmentStates:get(shelfUnit) ~= state then
        return
    end

    local attachmentRotation = buildAttachmentRotation(shelfConfig, shelfUnit)
    local attachmentOffset = buildLocalOffset(shelfConfig, task.rowIndex, task.columnIndex)
    local attachmentPosition = shelfUnit.get_local_offset_position(attachmentOffset)
    local attachmentUnit = GameAPI.create_unit_with_scale(
        shelfConfig.attachmentUnitKey,
        attachmentPosition,
        attachmentRotation,
        shelfConfig.attachmentScale
    )
    if attachmentUnit == nil then
        state.failedCount = state.failedCount + 1
        print(
            TAG,
            "create attachment failed, shelfId:",
            state.shelfId,
            "row:",
            task.rowIndex,
            "column:",
            task.columnIndex,
            "layerIndex:",
            task.layerIndex
        )
        return
    end

    state.spawnedCount = state.spawnedCount + 1
    recordAttachmentIndex(state, task, attachmentUnit)
    debugLog(
        "create attachment success, shelfId:",
        state.shelfId,
        "row:",
        task.rowIndex,
        "column:",
        task.columnIndex,
        "layerIndex:",
        task.layerIndex,
        "unit:",
        attachmentUnit
    )
end

---@param shelfUnit Unit
---@param shelfConfig table
---@param state table
local function onShelfSpawnFinished(shelfUnit, shelfConfig, state)
    print(
        TAG,
        "create shelf attachments done, shelfId:",
        state.shelfId,
        "success:",
        state.spawnedCount,
        "failed:",
        state.failedCount,
        "total:",
        state.totalCount
    )
    GlobalAPI.show_tips("货架补货完成，数量: " .. tostring(state.spawnedCount), SUCCESS_TIPS_DURATION)
    createShelfRowButtons(shelfUnit, shelfConfig, state)
end

---@param shelfUnit Unit|nil
---@param shelfConfig table
---@param enableSlowSpawn boolean
---@param deployTouchUseSuffix boolean
local function spawnAttachmentsOnShelf(shelfUnit, shelfConfig, enableSlowSpawn, deployTouchUseSuffix)
    if shelfUnit == nil then
        return
    end

    local spawnTasks = buildAttachmentSpawnTasks(shelfConfig)
    local totalCount = #spawnTasks
    local state = createShelfAttachmentState(
        shelfUnit,
        shelfConfig.shelfId,
        totalCount,
        shelfConfig.layout.rowCount,
        shelfConfig.layout.perRow,
        deployTouchUseSuffix
    )
    registerShelfDestroyEvents(shelfUnit, state)
    if totalCount == 0 then
        onShelfSpawnFinished(shelfUnit, shelfConfig, state)
        return
    end

    if not enableSlowSpawn then
        for taskIndex, task in ipairs(spawnTasks) do
            if state.destroyed or shelfAttachmentStates:get(shelfUnit) ~= state then
                return
            end
            spawnSingleAttachment(shelfUnit, shelfConfig, state, task)
            if taskIndex == totalCount then
                if not state.destroyed and shelfAttachmentStates:get(shelfUnit) == state then
                    onShelfSpawnFinished(shelfUnit, shelfConfig, state)
                end
            end
        end
        return
    end

    local nextTaskIndex = 0
    local timer = Timer.new(shelfConfig.spawnIntervalSec, true, totalCount)
    state.timer = timer
    timer:setTimeEndCb(function()
        if state.destroyed or shelfAttachmentStates:get(shelfUnit) ~= state then
            return
        end

        nextTaskIndex = nextTaskIndex + 1
        local task = spawnTasks[nextTaskIndex]
        if task ~= nil then
            spawnSingleAttachment(shelfUnit, shelfConfig, state, task)
        end

        if nextTaskIndex >= totalCount then
            state.timer = nil
            if not state.destroyed and shelfAttachmentStates:get(shelfUnit) == state then
                onShelfSpawnFinished(shelfUnit, shelfConfig, state)
            end
        end
    end)
    timer:start()
end

---@param actor Actor|nil
---@param data table|nil
local function destroyNextShelf(actor, data)
    if data == nil then
        print(TAG, "touch data nil: TestShelfDestroy", actor)
        return
    end

    local shelfUnit = popNextShelfToDestroy()
    if shelfUnit == nil then
        GlobalAPI.show_tips("暂无可销毁货架", ERROR_TIPS_DURATION)
        return
    end

    clearShelfAttachmentState(shelfUnit, nil, true)
    GameAPI.destroy_unit(shelfUnit)
    GlobalAPI.show_tips("已销毁队首货架，剩余: " .. tostring(#shelfDestroyQueue), SUCCESS_TIPS_DURATION)
end

function TestAttachmentHelper.init()
    if inited then
        return
    end

    local createForwardDistance = loadCreateForwardDistance()
    if createForwardDistance == nil then
        GlobalAPI.show_tips("配置错误：CREATE_FORWARD_DISTANCE", ERROR_TIPS_DURATION)
        return
    end

    local enableSlowSpawn = loadEnableSlowSpawn()
    if enableSlowSpawn == nil then
        GlobalAPI.show_tips("配置错误：ENABLE_SLOW_SPAWN", ERROR_TIPS_DURATION)
        return
    end

    local deployTouchUseSuffix = loadDeployTouchUseSuffix()
    if deployTouchUseSuffix == nil then
        GlobalAPI.show_tips("配置错误：DEPLOY_TOUCH_USE_SUFFIX", ERROR_TIPS_DURATION)
        return
    end

    local attachmentNode = UINodes.TestAttachmentCreate
    if attachmentNode == nil then
        print(TAG, "missing ui node: TestAttachmentCreate")
        GlobalAPI.show_tips("缺少节点 TestAttachmentCreate", ERROR_TIPS_DURATION)
    else
        LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, attachmentNode, 1 }, function(_, actor, data)
            if data == nil then
                print(TAG, "touch data nil: TestAttachmentCreate", actor)
                return
            end

            local runtimeShelfConfig, configErr = resolveRuntimeShelfConfig(nil)
            if runtimeShelfConfig == nil then
                if configErr == "missing" then
                    GlobalAPI.show_tips("缺少可用的货架配置", ERROR_TIPS_DURATION)
                else
                    GlobalAPI.show_tips("货架配置校验失败", ERROR_TIPS_DURATION)
                end
                return
            end

            createUnitInFront(
                data.role,
                runtimeShelfConfig.attachmentUnitKey,
                "Attachment",
                runtimeShelfConfig.attachmentScale,
                runtimeShelfConfig.attachmentRotationOffset,
                createForwardDistance
            )
        end)
    end

    local shelfNode = UINodes.TestShelfCreate
    if shelfNode == nil then
        print(TAG, "missing ui node: TestShelfCreate")
        GlobalAPI.show_tips("缺少节点 TestShelfCreate", ERROR_TIPS_DURATION)
        return
    end

    LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, shelfNode, 1 }, function(_, actor, data)
        if data == nil then
            print(TAG, "touch data nil: TestShelfCreate", actor)
            return
        end

        local requestedShelfId = nil -- 仅保留显式传参；如需指定货架，改为具体 shelfId 字符串
        local runtimeShelfConfig, configErr = resolveRuntimeShelfConfig(requestedShelfId)
        if runtimeShelfConfig == nil then
            if configErr == "missing" then
                GlobalAPI.show_tips("缺少可用的货架配置", ERROR_TIPS_DURATION)
            else
                GlobalAPI.show_tips("货架配置校验失败", ERROR_TIPS_DURATION)
            end
            return
        end

        local shelfUnit = createUnitInFront(
            data.role,
            runtimeShelfConfig.shelfUnitKey,
            "Shelf",
            runtimeShelfConfig.shelfScale,
            runtimeShelfConfig.shelfRotationOffset,
            createForwardDistance
        )
        if shelfUnit == nil then
            return
        end

        enqueueShelfForDestroy(shelfUnit)
        spawnAttachmentsOnShelf(shelfUnit, runtimeShelfConfig, enableSlowSpawn, deployTouchUseSuffix)
    end)

    local destroyNode = UINodes.TestShelfDestroy
    if destroyNode == nil then
        print(TAG, "missing ui node: TestShelfDestroy")
        GlobalAPI.show_tips("缺少节点 TestShelfDestroy", ERROR_TIPS_DURATION)
        return
    end

    LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, destroyNode, 1 }, function(_, actor, data)
        destroyNextShelf(actor, data)
    end)

    inited = true
end

return TestAttachmentHelper
