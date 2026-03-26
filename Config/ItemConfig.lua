local ItemConfig = {}
local Prefab = require("Data.Prefab")

local TAG = "[ItemConfig]"

local ITEM_ID = {
    TEST_MILK_SHAKE = "test_milk_shake", -- 测试奶昔
    TEST_BOMB = "test_bomb", -- 测试炸弹
}

local DEFAULT_ITEM_SCALE = math.Vector3(1.0, 1.0, 1.0) -- 物品默认缩放（DisplayComp.bind_model/create_unit_with_scale _scale）
local defaultItemIdQueueCursor = 0 -- 缺省 item 队列游标（启用队列轮换时使用，1-based）

ItemConfig.DEFAULT_ITEM_ID = ITEM_ID.TEST_MILK_SHAKE -- 默认 item 标识（通用默认选择）
ItemConfig.ENABLE_DEFAULT_ITEM_QUEUE = true -- 是否启用缺省 item 队列轮换（true: 按队列循环，false: 固定 DEFAULT_ITEM_ID）
ItemConfig.DEFAULT_ITEM_ID_QUEUE = { -- 缺省 item 队列（启用轮换时按顺序循环）
    ITEM_ID.TEST_MILK_SHAKE,
    ITEM_ID.TEST_BOMB,
}

local ITEM_DEFI = {
    [ITEM_ID.TEST_MILK_SHAKE] = {
        itemId = ITEM_ID.TEST_MILK_SHAKE, -- 物品标识（日志与排障定位）
        itemName = "Test Milk Shake", -- 物品名称（UI 显示）
        itemDesc = "A delicious test milk shake.", -- 物品描述（UI 显示）
        itemCount = 5, -- 物品数量（价格计算基数，整数）
        itemIcon = nil,
        itemScale = DEFAULT_ITEM_SCALE, -- 物品缩放（DisplayComp.bind_model/create_unit_with_scale _scale）
        itemPrefab = Prefab.unit.TestMilkShake,         -- 物品预制体（GameAPI.create_unit_with_scale/bind_model _u_key）
    },
    [ITEM_ID.TEST_BOMB] = {
        itemId = ITEM_ID.TEST_BOMB, -- 物品标识（日志与排障定位）
        itemName = "Test Bomb", -- 物品名称（UI 显示）
        itemDesc = "A powerful test bomb.", -- 物品描述（UI 显示）
        itemCount = 4, -- 物品数量（价格计算基数，整数）
        itemIcon = nil,
        itemScale = math.Vector3(0.7, 0.7, 0.7), -- 物品缩放（DisplayComp.bind_model/create_unit_with_scale _scale）
        itemPrefab = Prefab.unit.TestBomb, -- 物品预制体（GameAPI.create_unit_with_scale/bind_model _u_key）
    },
}

ItemConfig.ITEM_ID = ITEM_ID
ItemConfig.ITEM_DEFINITIONS = ITEM_DEFI

---@return string|nil
function ItemConfig.getDefaultItemId()
    if ItemConfig.ENABLE_DEFAULT_ITEM_QUEUE ~= true then
        return ItemConfig.DEFAULT_ITEM_ID
    end

    local defaultItemQueue = ItemConfig.DEFAULT_ITEM_ID_QUEUE
    if type(defaultItemQueue) ~= "table" or #defaultItemQueue == 0 then
        print(TAG, "invalid default item queue, fallback to DEFAULT_ITEM_ID")
        return ItemConfig.DEFAULT_ITEM_ID
    end

    local queueCount = #defaultItemQueue
    defaultItemIdQueueCursor = defaultItemIdQueueCursor % queueCount + 1
    local queueItemId = defaultItemQueue[defaultItemIdQueueCursor]
    if type(queueItemId) ~= "string" or queueItemId == "" then
        print(TAG, "invalid default queue item id, index:", defaultItemIdQueueCursor, "value:", queueItemId)
        return ItemConfig.DEFAULT_ITEM_ID
    end

    if ItemConfig.ITEM_DEFINITIONS[queueItemId] == nil then
        print(TAG, "default queue item definition not found, itemId:", queueItemId)
        return ItemConfig.DEFAULT_ITEM_ID
    end

    return queueItemId
end

---@param itemId string|nil
---@return table|nil
function ItemConfig.getItemById(itemId)
    if type(itemId) ~= "string" or itemId == "" then
        print(TAG, "invalid itemId:", itemId, "type:", type(itemId))
        return nil
    end

    local itemDef = ItemConfig.ITEM_DEFINITIONS[itemId]
    if itemDef == nil then
        print(TAG, "item definition not found, itemId:", itemId)
        return nil
    end

    return itemDef
end

return ItemConfig
