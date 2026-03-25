local ItemAttConfig = {}
local Prefab = require("Data.Prefab")
local TAG = "[ItemAttConfig]"

local CONFIG_IDS = {
    DEFAULT = "DefaultFrontBoxLayout",
    TWO_ROWS_FOUR = "TwoRowsFourItems",
    TWO_ROWS_FIVE = "TwoRowsFiveItems",
    THREE_ROWS_NINE = "ThreeRowsNineItems",
}

ItemAttConfig.DEFAULT_CONFIG_ID = CONFIG_IDS.THREE_ROWS_NINE -- 默认 ItemAtt 排布配置标识（匹配 ITEM_CONFIGS[*].configId）

ItemAttConfig.ITEM_CONFIGS = {
    {
        configId = CONFIG_IDS.DEFAULT, -- ItemAtt 排布配置标识（日志与排障定位）
        itemUnitKey = Prefab.unit.TestItem, -- item 预制体（GameAPI.create_unit_with_scale/bind_model _u_key）
        itemCount = 3, -- item 总数（自动排布输入，整数）
        rowCount = 1, -- 行数（自动排布输入，整数）
        xSpacing = 1.0, -- 同行横向间距（本地 x 轴，单位：米）
        zSpacing = 1.0, -- 行间纵向间距（本地 z 轴，单位：米）
        yOffset = 0.12, -- item 高度偏移（本地 y 轴，单位：米）
    },
    {
        configId = CONFIG_IDS.TWO_ROWS_FOUR, -- ItemAtt 排布配置标识（日志与排障定位）
        itemUnitKey = Prefab.unit.TestItem, -- item 预制体（GameAPI.create_unit_with_scale/bind_model _u_key）
        itemCount = 4, -- item 总数（自动排布输入，整数）
        rowCount = 2, -- 行数（自动排布输入，整数）
        xSpacing = 1.0, -- 同行横向间距（本地 x 轴，单位：米）
        zSpacing = 1.0, -- 行间纵向间距（本地 z 轴，单位：米）
        yOffset = 0.12, -- item 高度偏移（本地 y 轴，单位：米）
    },
    {
        configId = CONFIG_IDS.TWO_ROWS_FIVE, -- ItemAtt 排布配置标识（日志与排障定位）
        itemUnitKey = Prefab.unit.TestItem, -- item 预制体（GameAPI.create_unit_with_scale/bind_model _u_key）
        itemCount = 5, -- item 总数（自动排布输入，整数）
        rowCount = 2, -- 行数（自动排布输入，整数）
        xSpacing = 1.0, -- 同行横向间距（本地 x 轴，单位：米）
        zSpacing = 1.0, -- 行间纵向间距（本地 z 轴，单位：米）
        yOffset = 0.12, -- item 高度偏移（本地 y 轴，单位：米）
    },
    {
        configId = CONFIG_IDS.THREE_ROWS_NINE, -- ItemAtt 排布配置标识（日志与排障定位）
        itemUnitKey = Prefab.unit.TestItem, -- item 预制体（GameAPI.create_unit_with_scale/bind_model _u_key）
        itemCount = 9, -- item 总数（自动排布输入，整数）
        rowCount = 3, -- 行数（自动排布输入，整数）
        xSpacing = 1.0, -- 同行横向间距（本地 x 轴，单位：米）
        zSpacing = 1.0, -- 行间纵向间距（本地 z 轴，单位：米）
        yOffset = 0.12, -- item 高度偏移（本地 y 轴，单位：米）
    },
}

---@param configId string|nil
---@return table|nil
function ItemAttConfig.get_item_config_by_id(configId)
    local targetConfigId = configId
    if targetConfigId == nil then
        targetConfigId = ItemAttConfig.DEFAULT_CONFIG_ID
    end

    if type(targetConfigId) ~= "string" or targetConfigId == "" then
        print(TAG, "invalid configId:", targetConfigId, "type:", type(targetConfigId))
        return nil
    end

    for _, config in ipairs(ItemAttConfig.ITEM_CONFIGS or {}) do
        if config.configId == targetConfigId then
            return config
        end
    end

    if configId == nil then
        print(TAG, "default item att config not found, defaultConfigId:", targetConfigId)
    else
        print(TAG, "item att config not found, configId:", targetConfigId)
    end
    return nil
end

return ItemAttConfig
