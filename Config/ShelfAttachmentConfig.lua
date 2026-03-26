local ShelfAttachmentConfig = {}
local Prefab = require("Data.Prefab")
local TAG = "[ShelfAttachmentConfig]"

ShelfAttachmentConfig.CREATE_FORWARD_DISTANCE = 3.0 -- 生成到角色前方距离（Unit.get_position + Unit.get_local_direction，单位：米）
ShelfAttachmentConfig.ENABLE_SLOW_SPAWN = true -- 是否启用慢速生成（TestShelfCreate 的 Attachment 生成节奏开关）
ShelfAttachmentConfig.DEPLOY_TOUCH_USE_SUFFIX = true -- 是否使用 DeployBtn 后半截节点注册点击（true: EUI_NODE_TOUCH_EVENT，false: DeployBtnClicked 回退）

local SHELF_IDS = {
    BASIC_SHELF = "BasicShelf",
    BUILDIN_SHELF = "BuildInShelf",
}

ShelfAttachmentConfig.DEFAULT_SHELF_ID = SHELF_IDS.BASIC_SHELF -- 默认使用的 Shelf 配置标识（匹配 SHELF_CONFIGS[*].shelfId）

ShelfAttachmentConfig.SHELF_CONFIGS = {
    {
        shelfId = SHELF_IDS.BASIC_SHELF, -- Shelf 配置标识（日志与排障定位）

        shelfUnitKey = Prefab.unit.BasicShelf, -- Shelf 预制体（GameAPI.create_unit_with_scale _u_key）
        shelfScale = { x = -0.12, y = 6.73, z = 8.34 }, -- Shelf 缩放（GameAPI.create_unit_with_scale _scale）
        shelfRotationOffsetEulerDeg = { x = 0.0, y = -90.0, z = 0.0 }, -- Shelf 朝向修正（_rotation 欧拉角，单位：度）

        attachmentUnitKey = Prefab.unit.Attachment, -- Attachment 预制体（GameAPI.create_unit_with_scale _u_key）
        attachmentScale = { x = 0.1, y = 0.1, z = 0.1 }, -- Attachment 缩放（GameAPI.create_unit_with_scale _scale）
        attachmentRotationOffsetEulerDeg = { x = 0.0, y = 0.0, z = 0.0 }, -- Attachment 自身朝向修正（最终朝向=shelf朝向*该偏移，单位：度）
        spawnIntervalSec = 0.05, -- 慢速生成间隔（Timer.new duration，单位：秒）

        layout = {
            rowCount = 4, -- 货架排数（整数）
            perRow = 6, -- 每排 Attachment 数量（整数）
            firstRowHeight = 0.7, -- 第一排中心高度（Unit.get_local_offset_position _offset，基准：模型本地原点，单位：米）
            rowHeightStep = 1.55, -- 相邻排高度差（Unit.get_local_offset_position _offset，单位：米）
            columnSpacing = 1.0, -- 同排间距（Unit.get_local_offset_position _offset，单位：米）
            columnOffset = 0.0, -- 整排横向偏移（Unit.get_local_offset_position _offset，单位：米）
            depthOffset = 1, -- 整排纵深偏移（Unit.get_local_offset_position _offset，单位：米）

            axisMap = {
                columnAxis = "z", -- 横向使用的本地轴（x|y|z）
                columnSign = 1, -- 横向方向符号（1 正向，-1 反向）
                heightAxis = "y", -- 高度使用的本地轴（x|y|z）
                heightSign = 1, -- 高度方向符号（1 正向，-1 反向）
                depthAxis = "x", -- 纵深使用的本地轴（x|y|z）
                depthSign = 1, -- 纵深方向符号（1 正向，-1 反向）
            },
        },
    },
    {
        shelfId = SHELF_IDS.BUILDIN_SHELF,                                -- Shelf 配置标识（日志与排障定位）

        shelfUnitKey = Prefab.unit.BuildinShelf,                            -- Shelf 预制体（GameAPI.create_unit_with_scale _u_key）
        shelfScale = { x = 1.62, y = 1.62, z = 2.80 },                   -- Shelf 缩放（GameAPI.create_unit_with_scale _scale）
        shelfRotationOffsetEulerDeg = { x = 0.0, y = -90.0, z = 0.0 },    -- Shelf 朝向修正（_rotation 欧拉角，单位：度）

        attachmentUnitKey = Prefab.unit.Attachment,                       -- Attachment 预制体（GameAPI.create_unit_with_scale _u_key）
        attachmentScale = { x = 0.1, y = 0.1, z = 0.1 },                  -- Attachment 缩放（GameAPI.create_unit_with_scale _scale）
        attachmentRotationOffsetEulerDeg = { x = 0.0, y = 0.0, z = 0.0 }, -- Attachment 自身朝向修正（最终朝向=shelf朝向*该偏移，单位：度）
        spawnIntervalSec = 0.05,                                           -- 慢速生成间隔（Timer.new duration，单位：秒）

        layout = {
            rowCount = 3,         -- 货架排数（整数）
            perRow = 6,           -- 每排 Attachment 数量（整数）
            firstRowHeight = 0.7, -- 第一排中心高度（Unit.get_local_offset_position _offset，基准：模型本地原点，单位：米）
            rowHeightStep = 1.7,  -- 相邻排高度差（Unit.get_local_offset_position _offset，单位：米）
            columnSpacing = 1.0,  -- 同排间距（Unit.get_local_offset_position _offset，单位：米）
            columnOffset = 0.0,   -- 整排横向偏移（Unit.get_local_offset_position _offset，单位：米）
            depthOffset = 0,      -- 整排纵深偏移（Unit.get_local_offset_position _offset，单位：米）

            axisMap = {
                columnAxis = "z", -- 横向使用的本地轴（x|y|z）
                columnSign = 1,   -- 横向方向符号（1 正向，-1 反向）
                heightAxis = "y", -- 高度使用的本地轴（x|y|z）
                heightSign = 1,   -- 高度方向符号（1 正向，-1 反向）
                depthAxis = "x",  -- 纵深使用的本地轴（x|y|z）
                depthSign = 1,    -- 纵深方向符号（1 正向，-1 反向）
            },
        },
    },
}

---@param shelfId string|nil
---@return table|nil
function ShelfAttachmentConfig.get_shelf_config_by_id(shelfId)
    local targetShelfId = shelfId
    if targetShelfId == nil then
        targetShelfId = ShelfAttachmentConfig.DEFAULT_SHELF_ID
    end

    if type(targetShelfId) ~= "string" or targetShelfId == "" then
        print(TAG, "invalid shelfId:", targetShelfId, "type:", type(targetShelfId))
        return nil
    end

    for _, shelfConfig in ipairs(ShelfAttachmentConfig.SHELF_CONFIGS or {}) do
        if shelfConfig.shelfId == targetShelfId then
            return shelfConfig
        end
    end

    if shelfId == nil then
        print(TAG, "default shelf config not found, defaultShelfId:", targetShelfId)
    else
        print(TAG, "shelf config not found, shelfId:", targetShelfId)
    end

    return nil
end

return ShelfAttachmentConfig
