local TestAttactmentHelper = {}

local TAG = "[TestAttactmentHelper]"
local Timer = require("Utils.Timer")
local UINodes = require("Data.UINodes")
local ShelfAttachmentConfig = require("Config.ShelfAttachmentConfig")

local SUCCESS_TIPS_DURATION = 2.0 -- 成功提示时长（GlobalAPI.show_tips _duration，单位：秒）
local ERROR_TIPS_DURATION = 3.0 -- 失败提示时长（GlobalAPI.show_tips _duration，单位：秒）
local DEFAULT_SCALE = math.Vector3(1.0, 1.0, 1.0) -- 默认缩放（GameAPI.create_unit_with_scale _scale）
local DEFAULT_ROTATION_OFFSET = math.Quaternion(0.0, 0.0, 0.0) -- 默认旋转偏移（GameAPI.create_unit_with_scale _rotation）

local AXIS_ENUM = {
    x = true,
    y = true,
    z = true,
}

local shelfAttachmentStates = dict()

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
---@param shelfId string
---@param totalCount integer
---@return table
local function createShelfAttachmentState(shelfUnit, shelfId, totalCount)
    local oldState = shelfAttachmentStates:get(shelfUnit)
    if oldState ~= nil and oldState.timer ~= nil then
        oldState.timer:cancel()
    end

    local state = {
        shelfId = shelfId,
        totalCount = totalCount,
        spawnedCount = 0,
        failedCount = 0,
        timer = nil,
        layers = {},
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
        unit = attachmentUnit,
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
    print(
        TAG,
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

---@param state table
local function onShelfSpawnFinished(state)
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
end

---@param shelfUnit Unit|nil
---@param shelfConfig table
---@param enableSlowSpawn boolean
local function spawnAttachmentsOnShelf(shelfUnit, shelfConfig, enableSlowSpawn)
    if shelfUnit == nil then
        return
    end

    local spawnTasks = buildAttachmentSpawnTasks(shelfConfig)
    local totalCount = #spawnTasks
    local state = createShelfAttachmentState(shelfUnit, shelfConfig.shelfId, totalCount)
    if totalCount == 0 then
        onShelfSpawnFinished(state)
        return
    end

    if not enableSlowSpawn then
        for taskIndex, task in ipairs(spawnTasks) do
            spawnSingleAttachment(shelfUnit, shelfConfig, state, task)
            if taskIndex == totalCount then
                onShelfSpawnFinished(state)
            end
        end
        return
    end

    local nextTaskIndex = 0
    local timer = Timer.new(shelfConfig.spawnIntervalSec, true, totalCount)
    state.timer = timer
    timer:setTimeEndCb(function()
        nextTaskIndex = nextTaskIndex + 1
        local task = spawnTasks[nextTaskIndex]
        if task ~= nil then
            spawnSingleAttachment(shelfUnit, shelfConfig, state, task)
        end

        if nextTaskIndex >= totalCount then
            state.timer = nil
            onShelfSpawnFinished(state)
        end
    end)
    timer:start()
end

function TestAttactmentHelper.init()
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

        spawnAttachmentsOnShelf(shelfUnit, runtimeShelfConfig, enableSlowSpawn)
    end)
end

return TestAttactmentHelper
