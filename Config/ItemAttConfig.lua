local ItemAttConfig = {}
local ItemConfig = require("Config.ItemConfig")
local TAG = "[ItemAttConfig]"

local ITEM_ID = ItemConfig.ITEM_ID

ItemAttConfig.ITEM_ATT_DEFI = {
    [ITEM_ID.TEST_MILK_SHAKE] = {
        rowCount = 2, -- 行数（自动排布输入，整数）
        xSpacing = 1.0, -- 同行横向间距（本地 x 轴，单位：米）
        zSpacing = 1.0, -- 行间纵向间距（本地 z 轴，单位：米）
        yOffset = 0.12, -- item 高度偏移（本地 y 轴，单位：米）
    },
    [ITEM_ID.TEST_BOMB] = {
        rowCount = 2, -- 行数（自动排布输入，整数）
        xSpacing = 1.1, -- 同行横向间距（本地 x 轴，单位：米）
        zSpacing = 1.1, -- 行间纵向间距（本地 z 轴，单位：米）
        yOffset = 0.12, -- item 高度偏移（本地 y 轴，单位：米）
    },
}

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

---@param itemId string
---@param fieldPath string
---@param value any
local function logItemAttFieldError(itemId, fieldPath, value)
    print(TAG, "invalid item att config field, itemId:", itemId, "field:", fieldPath, "value:", value, "type:", type(value))
end

---@param itemId string
---@param fieldPath string
---@param value any
---@return integer|nil
local function parsePositiveInteger(itemId, fieldPath, value)
    if type(value) ~= "number" or value ~= math.floor(value) then
        logItemAttFieldError(itemId, fieldPath, value)
        return nil
    end

    local integerValue = math.tointeger(value)
    if integerValue == nil or integerValue <= 0 then
        logItemAttFieldError(itemId, fieldPath, value)
        return nil
    end
    return integerValue
end

---@param itemId string
---@param fieldPath string
---@param value any
---@return number|nil
local function parseNumber(itemId, fieldPath, value)
    if not isPlatformNumber(value) then
        logItemAttFieldError(itemId, fieldPath, value)
        return nil
    end
    return toRealNumber(value)
end

---@param itemId string
---@param fieldPath string
---@param value any
---@return Vector3|nil
local function parseVector3(itemId, fieldPath, value)
    local valueType = type(value)
    if valueType ~= "table" and valueType ~= "Vector3" then
        logItemAttFieldError(itemId, fieldPath, value)
        return nil
    end

    local x = parseNumber(itemId, fieldPath .. ".x", value.x)
    local y = parseNumber(itemId, fieldPath .. ".y", value.y)
    local z = parseNumber(itemId, fieldPath .. ".z", value.z)
    if x == nil or y == nil or z == nil then
        return nil
    end

    return math.Vector3(x, y, z)
end

---@param itemId string
---@param itemAttDef table
---@return table|nil
local function resolveItemAttDef(itemId, itemAttDef)
    local itemDef = ItemConfig.getItemById(itemId)
    if itemDef == nil then
        print(TAG, "missing item definition, itemId:", itemId)
        return nil
    end

    local itemUnitKey = itemDef.itemPrefab
    if type(itemUnitKey) ~= "number" or itemUnitKey ~= math.floor(itemUnitKey) then
        print(
            TAG,
            "invalid item prefab unit key, itemId:",
            itemId,
            "value:",
            itemUnitKey,
            "type:",
            type(itemUnitKey)
        )
        return nil
    end

    local unitKeyInteger = math.tointeger(itemUnitKey)
    if unitKeyInteger == nil or unitKeyInteger <= 0 then
        print(TAG, "invalid integer item unit key, itemId:", itemId, "value:", itemUnitKey)
        return nil
    end

    local itemScale = parseVector3(itemId, "itemScale", itemDef.itemScale)
    if itemScale == nil then
        return nil
    end

    local itemCount = parsePositiveInteger(itemId, "itemCount", itemDef.itemCount)
    local rowCount = parsePositiveInteger(itemId, "rowCount", itemAttDef.rowCount)
    local xSpacing = parseNumber(itemId, "xSpacing", itemAttDef.xSpacing)
    local zSpacing = parseNumber(itemId, "zSpacing", itemAttDef.zSpacing)
    local yOffset = parseNumber(itemId, "yOffset", itemAttDef.yOffset)
    if itemCount == nil or rowCount == nil or xSpacing == nil or zSpacing == nil or yOffset == nil then
        return nil
    end
    if xSpacing < 0.0 then
        logItemAttFieldError(itemId, "xSpacing", itemAttDef.xSpacing)
        return nil
    end
    if zSpacing < 0.0 then
        logItemAttFieldError(itemId, "zSpacing", itemAttDef.zSpacing)
        return nil
    end

    return {
        itemId = itemId,
        itemUnitKey = unitKeyInteger,
        itemScale = itemScale,
        itemCount = itemCount,
        rowCount = rowCount,
        xSpacing = xSpacing,
        zSpacing = zSpacing,
        yOffset = yOffset,
    }
end

---@param itemId string|nil
---@return table|nil
function ItemAttConfig.getItemAttDefByItemId(itemId)
    local targetItemId = itemId
    if targetItemId == nil then
        targetItemId = ItemConfig.getDefaultItemId()
    end

    if type(targetItemId) ~= "string" or targetItemId == "" then
        print(TAG, "invalid itemId:", targetItemId, "type:", type(targetItemId))
        return nil
    end

    local itemAttDef = (ItemAttConfig.ITEM_ATT_DEFI or {})[targetItemId]
    if itemAttDef == nil then
        print(TAG, "item att defi not found, itemId:", targetItemId)
        return nil
    end

    return resolveItemAttDef(targetItemId, itemAttDef)
end

return ItemAttConfig
