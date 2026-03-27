local TestShelfConsumeThread = {}

local TAG = "[TestShelfConsumeThread]"
local Timer = require("Utils.Timer")
local ItemConfig = require("Config.ItemConfig")
local TestAttachmentHelper = require("TestAttachmentHelper")

local SHELF_CONSUME_INTERVAL_SEC = 2.0 -- 每货架消费线程周期（Timer.new duration，单位：秒）
local SHELF_SYNC_INTERVAL_SEC = 0.5 -- 活跃货架同步周期（Timer.new duration，单位：秒）
local INTENT_REQUEST_COUNT = 1 -- 测试意图单次请求数量；后续由真实顾客请求参数驱动（consumeItemsByIntent requestCount，单位：个）

local shelfConsumeTimers = dict()
local trackedShelfUnits = {}
local syncTimer = nil
local intentItemPool = {}
local inited = false

---@param shelfUnit Unit|nil
local function removeTrackedShelfUnit(shelfUnit)
    if shelfUnit == nil then
        return
    end

    for index = #trackedShelfUnits, 1, -1 do
        if trackedShelfUnits[index] == shelfUnit then
            table.remove(trackedShelfUnits, index)
        end
    end
end

---@param shelfUnit Unit|nil
local function stopShelfConsumeTimer(shelfUnit)
    if shelfUnit == nil then
        return
    end

    local timer = shelfConsumeTimers:get(shelfUnit)
    if timer ~= nil then
        timer:cancel()
    end
    shelfConsumeTimers:set(shelfUnit, nil)
    removeTrackedShelfUnit(shelfUnit)
end

local function rebuildIntentItemPool()
    intentItemPool = {}
    local itemDefinitions = ItemConfig.ITEM_DEFINITIONS
    if type(itemDefinitions) ~= "table" then
        return
    end

    for itemId, _ in pairs(itemDefinitions) do
        if type(itemId) == "string" and itemId ~= "" then
            intentItemPool[#intentItemPool + 1] = itemId
        end
    end
end

---@return string|nil
local function pickRandomIntentItemId()
    local poolSize = #intentItemPool
    if poolSize <= 0 then
        return nil
    end

    -- 当前使用随机意图模拟顾客选择；后续可替换为顾客系统传入的目标 itemId。
    local randomIndex = GameAPI.random_int(1, poolSize)
    if type(randomIndex) ~= "number" then
        return nil
    end

    local randomIndexInteger = math.tointeger(randomIndex)
    if randomIndexInteger == nil or randomIndexInteger < 1 or randomIndexInteger > poolSize then
        return nil
    end
    return intentItemPool[randomIndexInteger]
end

---@param shelfUnit Unit
local function ensureShelfConsumeTimer(shelfUnit)
    if shelfConsumeTimers:get(shelfUnit) ~= nil then
        return
    end

    local consumeTimer = Timer.new(SHELF_CONSUME_INTERVAL_SEC, true)
    shelfConsumeTimers:set(shelfUnit, consumeTimer)
    trackedShelfUnits[#trackedShelfUnits + 1] = shelfUnit
    consumeTimer:setTimeEndCb(function()
        if not TestAttachmentHelper.isShelfActive(shelfUnit) then
            stopShelfConsumeTimer(shelfUnit)
            return
        end

        local intentItemId = pickRandomIntentItemId()
        if intentItemId == nil then
            return
        end

        local consumedCount, consumedItems = TestAttachmentHelper.consumeItemsByIntent(shelfUnit, intentItemId, INTENT_REQUEST_COUNT)
        if consumedCount > 0 then
            print(
                TAG,
                "consume intent success, shelfUnit:",
                shelfUnit,
                "itemId:",
                intentItemId,
                "count:",
                consumedCount,
                "detailCount:",
                #consumedItems
            )
        end
    end)
    consumeTimer:start()
end

local function syncActiveShelfConsumeThreads()
    -- 仅测试场景使用“活跃货架自动发现 + 线程挂载”；正式流程计划改为按目标货架发起消费请求。
    local activeShelfUnits = TestAttachmentHelper.getActiveShelfUnits()
    local activeShelfSet = dict()

    for _, shelfUnit in ipairs(activeShelfUnits) do
        activeShelfSet:set(shelfUnit, true)
        ensureShelfConsumeTimer(shelfUnit)
    end

    for index = #trackedShelfUnits, 1, -1 do
        local shelfUnit = trackedShelfUnits[index]
        if activeShelfSet:get(shelfUnit) ~= true then
            stopShelfConsumeTimer(shelfUnit)
        end
    end
end

function TestShelfConsumeThread.init()
    if inited then
        return
    end

    rebuildIntentItemPool()
    if #intentItemPool <= 0 then
        print(TAG, "empty intent item pool, consume thread disabled")
        return
    end

    syncActiveShelfConsumeThreads()
    syncTimer = Timer.new(SHELF_SYNC_INTERVAL_SEC, true)
    syncTimer:setTimeEndCb(function()
        local ok, err = pcall(function()
            syncActiveShelfConsumeThreads()
        end)
        if not ok then
            print(TAG, "sync active shelves crashed, err:", tostring(err))
        end
    end)
    syncTimer:start()

    inited = true
end

return TestShelfConsumeThread
