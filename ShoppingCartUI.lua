local UINodes = require("Data.UINodes")
local GuiUtils = require("Utils.GuiUtils")
local ShoppingCartConfig = require("Config.ShoppingCartConfig")
local ShoppingCartUI = {}

-- 购物车 UI 模块：
-- 1) 维护左侧待购状态 + 右侧购物车状态
-- 2) 通过 view model 构建与渲染统一刷新左右 UI
-- 3) 绑定左右按钮事件并驱动状态变更

local MAX_PRODUCTS = ShoppingCartConfig.MAX_PRODUCTS
local MAX_CART_ROWS = ShoppingCartConfig.MAX_CART_ROWS
local MAX_AMOUNT_PER_PRODUCT = ShoppingCartConfig.MAX_AMOUNT_PER_PRODUCT
local GRID_ITEMS_PER_LINE = (math and math.tointeger and math.tointeger(ShoppingCartConfig.GRID_ITEMS_PER_LINE)) or ShoppingCartConfig.GRID_ITEMS_PER_LINE
if GRID_ITEMS_PER_LINE == nil or GRID_ITEMS_PER_LINE < 1 then
    GRID_ITEMS_PER_LINE = 1
end

local PRODUCT_CONFIG = ShoppingCartConfig.PRODUCT_CONFIG
local PRODUCT_COUNT = math.min(MAX_PRODUCTS, #PRODUCT_CONFIG)
local LEFT_GRID_NODE_NAMING = ShoppingCartConfig.LEFT_GRID_NODE_NAMING
local RIGHT_LIST_NODE_NAMING = ShoppingCartConfig.RIGHT_LIST_NODE_NAMING
local CART_PANEL_NODE_NAMES = ShoppingCartConfig.CART_PANEL_NODE_NAMES
local UI_TOUCH_EVENT_TYPES = ShoppingCartConfig.UI_TOUCH_EVENT_TYPES

local ENABLE_INDEX_TRACE = false
local missingNodeWarned = {}
local missingProductWarned = {}
local overflowWarnedBySignature = {}

-- 模块内状态：
-- pendingCaseCountByProduct: 左侧每个商品“待加入购物车”的箱数
-- cartCaseCountByProduct:    右侧购物车每个商品当前箱数
-- cartRowProductIndices:     右侧行号 -> 商品下标（由 buildRightViewModel 刷新）
-- activeCartRows:            右侧实际可用行数（运行时检测）
-- initialized:               防重复初始化
local state = {
    pendingCaseCountByProduct = {},
    cartCaseCountByProduct = {},
    cartRowProductIndices = {},
    activeCartRows = 0,
    initialized = false,
}

local function warn(content)
    GlobalAPI.warning("[ShoppingCartUI] " .. content)
end

local function traceIndex(message)
    if ENABLE_INDEX_TRACE then
        warn("[IndexTrace] " .. message)
    end
end

local function ensureIntegerIndex(value, source)
    local sourceName = source or "unknown"
    if value == nil then
        traceIndex(sourceName .. " 输入为 nil")
        return nil
    end

    if math and math.tointeger then
        local intValue = math.tointeger(value)
        if intValue ~= nil then
            if type(value) ~= "number" or value ~= intValue then
                traceIndex(string.format("%s 非整数输入: raw=%s rawType=%s", sourceName, tostring(value), type(value)))
            end
            return intValue
        end
    end

    traceIndex(string.format("%s 非法索引: raw=%s rawType=%s", sourceName, tostring(value), type(value)))
    return nil
end

if MAX_PRODUCTS ~= #PRODUCT_CONFIG then
    warn(string.format("MAX_PRODUCTS(%d) 与 PRODUCT_CONFIG 数量(%d)不一致，按较小值 %d 运行", MAX_PRODUCTS, #PRODUCT_CONFIG, PRODUCT_COUNT))
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function formatMoney(value)
    return string.format("¥%.2f", value)
end

local function getNode(nodeName)
    local node = UINodes[nodeName]
    if node == nil and not missingNodeWarned[nodeName] then
        warn("未找到节点: " .. nodeName)
        missingNodeWarned[nodeName] = true
    end
    return node
end

local function hasNodeName(nodeName)
    return UINodes[nodeName] ~= nil
end

local function uiSetLabel(node, text)
    if node == nil then
        return
    end
    -- TODO(UI): 文本更新统一入口。
    GuiUtils.setLabelText(node, text)
end

local function uiShow(node)
    if node == nil then
        return
    end
    -- TODO(UI): 节点显示统一入口。
    GuiUtils.showNode(node)
end

local function uiHide(node)
    if node == nil then
        return
    end
    -- TODO(UI): 节点隐藏统一入口。
    GuiUtils.hideNode(node)
end

local function getProductConfig(productIndex)
    local index = ensureIntegerIndex(productIndex, "getProductConfig.productIndex")
    if index == nil then
        warn("商品下标非法: " .. tostring(productIndex))
        return nil
    end

    local product = PRODUCT_CONFIG[index]
    if product == nil and not missingProductWarned[index] then
        warn("未找到商品配置，下标: " .. tostring(index))
        missingProductWarned[index] = true
    end
    return product
end

local function getCaseUnitCount(productIndex)
    local product = getProductConfig(productIndex)
    if product == nil then
        return 0
    end
    return product.caseCount
end

local function getCasePrice(productIndex)
    local product = getProductConfig(productIndex)
    if product == nil then
        return 0
    end
    return product.unitPrice * getCaseUnitCount(productIndex)
end

local function getProductSlot(productIndex)
    local index = ensureIntegerIndex(productIndex, "getProductSlot.productIndex")
    if index == nil then
        return 1, 1
    end

    local zeroBasedIndex = index - 1
    local line = (zeroBasedIndex // GRID_ITEMS_PER_LINE) + 1
    local col = (zeroBasedIndex % GRID_ITEMS_PER_LINE) + 1

    line = ensureIntegerIndex(line, "getProductSlot.line") or line
    col = ensureIntegerIndex(col, "getProductSlot.col") or col
    return line, col
end

local function getLeftGridNodeNames(line, col)
    return {
        itemName = string.format("%s_%d_%d", LEFT_GRID_NODE_NAMING.itemNamePrefix, line, col),
        unitPrice = string.format("%s_%d_%d", LEFT_GRID_NODE_NAMING.unitPricePrefix, line, col),
        amountLabel = string.format("%s_%d_%d", LEFT_GRID_NODE_NAMING.amountLabelPrefix, line, col),
        purchaseAmountLabel = string.format("%s_%d_%d", LEFT_GRID_NODE_NAMING.purchaseAmountLabelPrefix, line, col),
        casePriceLabel = string.format("%s_%d_%d", LEFT_GRID_NODE_NAMING.casePriceLabelPrefix, line, col),
        addButton = string.format("%s_%d_%d", LEFT_GRID_NODE_NAMING.addButtonPrefix, line, col),
        decButton = string.format("%s_%d_%d", LEFT_GRID_NODE_NAMING.decButtonPrefix, line, col),
        purchaseButton = string.format("%s_%d_%d", LEFT_GRID_NODE_NAMING.purchaseButtonPrefix, line, col),
    }
end

local function getRightRowNodeNames(row)
    return {
        root = string.format("%s_%d", RIGHT_LIST_NODE_NAMING.rootPrefix, row),
        itemName = string.format("%s_%d", RIGHT_LIST_NODE_NAMING.itemNamePrefix, row),
        subTotal = string.format("%s_%d", RIGHT_LIST_NODE_NAMING.subTotalPrefix, row),
        amount = string.format("%s_%d", RIGHT_LIST_NODE_NAMING.amountPrefix, row),
        addButton = string.format("%s_%d", RIGHT_LIST_NODE_NAMING.addButtonPrefix, row),
        decButton = string.format("%s_%d", RIGHT_LIST_NODE_NAMING.decButtonPrefix, row),
    }
end

local function buildCartOrderedIndices()
    -- 右侧清单压缩显示顺序：按商品配置顺序筛选“购物车数量 > 0”的商品。
    local ordered = {}
    for productIndex = 1, PRODUCT_COUNT do
        local index = ensureIntegerIndex(productIndex, "buildCartOrderedIndices.loopIndex")
        if index ~= nil and (state.cartCaseCountByProduct[index] or 0) > 0 then
            table.insert(ordered, index)
        end
    end
    return ordered
end

local function buildLeftViewModel()
    -- 左侧 VM 只负责“显示数据准备”，不做 UI 操作。
    local vm = { items = {} }

    for productIndex = 1, PRODUCT_COUNT do
        local index = ensureIntegerIndex(productIndex, "buildLeftViewModel.loopIndex")
        if index ~= nil then
            local product = getProductConfig(index)
            if product ~= nil then
                local line, col = getProductSlot(index)
                local pendingCaseCount = state.pendingCaseCountByProduct[index] or 1
                local pendingTotal = getCasePrice(index) * pendingCaseCount
                local nodeNames = getLeftGridNodeNames(line, col)

                table.insert(vm.items, {
                    index = index,
                    line = line,
                    col = col,
                    nodeNames = nodeNames,
                    name = product.name,
                    unitPriceText = string.format("%.2f", product.unitPrice),
                    caseCountText = tostring(getCaseUnitCount(index)),
                    pendingCaseCountText = tostring(pendingCaseCount),
                    pendingTotalText = formatMoney(pendingTotal),
                })
            end
        end
    end

    return vm
end

local function buildRightViewModel()
    -- 右侧 VM 负责：
    -- 1) 根据购物车状态生成压缩行
    -- 2) 同步维护 row -> productIndex 映射供右侧按钮事件反查
    -- 3) 计算总价文本
    -- 行顺序稳定策略：
    -- 先沿用上一次已显示行中的顺序（仍有数量的商品保留原位次），
    -- 再把本轮新出现的商品追加到末尾，避免随机增删导致行跳动。
    local orderedByProduct = buildCartOrderedIndices()
    local ordered = {}
    local exists = {}
    local vm = { rows = {}, totalPriceText = formatMoney(0) }
    local totalPrice = 0

    local previousRowProductIndices = state.cartRowProductIndices

    for row = 1, state.activeCartRows do
        local productIndex = ensureIntegerIndex(previousRowProductIndices[row], "buildRightViewModel.previousRowProductIndex")
        if productIndex ~= nil and (state.cartCaseCountByProduct[productIndex] or 0) > 0 and not exists[productIndex] then
            table.insert(ordered, productIndex)
            exists[productIndex] = true
        end
    end

    for _, productIndex in ipairs(orderedByProduct) do
        if not exists[productIndex] then
            table.insert(ordered, productIndex)
            exists[productIndex] = true
        end
    end

    state.cartRowProductIndices = {}
    for row = 1, state.activeCartRows do
        local rowNodeNames = getRightRowNodeNames(row)
        local productIndex = ensureIntegerIndex(ordered[row], "buildRightViewModel.rowProductIndex")
        state.cartRowProductIndices[row] = productIndex

        if productIndex then
            local product = getProductConfig(productIndex)
            if product ~= nil then
                local cartCaseCount = state.cartCaseCountByProduct[productIndex] or 0
                local subTotal = getCasePrice(productIndex) * cartCaseCount
                table.insert(vm.rows, {
                    row = row,
                    visible = true,
                    nodeNames = rowNodeNames,
                    name = product.name,
                    amountText = tostring(cartCaseCount),
                    subTotalText = formatMoney(subTotal),
                })
            else
                table.insert(vm.rows, {
                    row = row,
                    visible = false,
                    nodeNames = rowNodeNames,
                    name = "",
                    amountText = "",
                    subTotalText = "",
                })
            end
        else
            table.insert(vm.rows, {
                row = row,
                visible = false,
                nodeNames = rowNodeNames,
                name = "",
                amountText = "",
                subTotalText = "",
            })
        end
    end

    for productIndex = 1, PRODUCT_COUNT do
        local index = ensureIntegerIndex(productIndex, "buildRightViewModel.total.loopIndex")
        if index ~= nil then
            local cartCaseCount = state.cartCaseCountByProduct[index] or 0
            if cartCaseCount > 0 then
                totalPrice = totalPrice + (getCasePrice(index) * cartCaseCount)
            end
        end
    end

    if #ordered > state.activeCartRows then
        local signature = string.format("%d>%d", #ordered, state.activeCartRows)
        if not overflowWarnedBySignature[signature] then
            warn(string.format("右侧清单行数不足：有 %d 个商品在购物车中，仅可显示 %d 行；超出部分不显示但会计入总价", #ordered, state.activeCartRows))
            overflowWarnedBySignature[signature] = true
        end
    end

    vm.totalPriceText = formatMoney(totalPrice)
    return vm
end

local function renderLeft(vm)
    -- 左侧渲染层只落地文本，不做状态计算。
    for _, item in ipairs(vm.items) do
        local nodes = item.nodeNames
        uiSetLabel(getNode(nodes.itemName), item.name)
        uiSetLabel(getNode(nodes.unitPrice), item.unitPriceText)
        uiSetLabel(getNode(nodes.amountLabel), item.caseCountText)
        uiSetLabel(getNode(nodes.purchaseAmountLabel), item.pendingCaseCountText)
        uiSetLabel(getNode(nodes.casePriceLabel), item.pendingTotalText)
    end
end

local function renderRight(vm)
    -- 右侧渲染层只负责显示/隐藏与文本更新。
    for _, row in ipairs(vm.rows) do
        local nodes = row.nodeNames
        local rootNode = getNode(nodes.root)

        if row.visible then
            uiShow(rootNode)
            uiSetLabel(getNode(nodes.itemName), row.name)
            uiSetLabel(getNode(nodes.subTotal), row.subTotalText)
            uiSetLabel(getNode(nodes.amount), row.amountText)
        else
            uiHide(rootNode)
            uiSetLabel(getNode(nodes.itemName), "")
            uiSetLabel(getNode(nodes.subTotal), "")
            uiSetLabel(getNode(nodes.amount), "")
        end
    end

    uiSetLabel(getNode(CART_PANEL_NODE_NAMES.totalValue), vm.totalPriceText)
end

local function refreshUI(reason)
    -- 统一刷新入口：状态 -> VM -> 渲染
    -- reason 仅用于调用语义标记，便于后续排查扩展。
    local _reason = reason
    local leftVM = buildLeftViewModel()
    local rightVM = buildRightViewModel()
    renderLeft(leftVM)
    renderRight(rightVM)
end

local function renderRightStaticText()
    -- 静态文案仅初始化时设置一次。
    uiSetLabel(getNode(CART_PANEL_NODE_NAMES.cartTitle), "购物车")
    uiSetLabel(getNode(CART_PANEL_NODE_NAMES.listTitleItemName), "商品项")
    uiSetLabel(getNode(CART_PANEL_NODE_NAMES.listTitleItemTotalValue), "小计")
    uiSetLabel(getNode(CART_PANEL_NODE_NAMES.listTitleItemAmount), "数量")
    uiSetLabel(getNode(CART_PANEL_NODE_NAMES.totalText), "总计")
    uiSetLabel(getNode(CART_PANEL_NODE_NAMES.purchaseButtonText), "购买")
end

local function setPendingCaseCount(productIndex, targetCount)
    local index = ensureIntegerIndex(productIndex, "setPendingCaseCount.productIndex")
    if index == nil then
        return
    end
    local safeCount = clamp(targetCount, 1, MAX_AMOUNT_PER_PRODUCT)
    state.pendingCaseCountByProduct[index] = safeCount
end

local function changePendingCaseCount(productIndex, delta)
    local index = ensureIntegerIndex(productIndex, "changePendingCaseCount.productIndex")
    if index == nil then
        return
    end
    local oldCount = state.pendingCaseCountByProduct[index] or 1
    setPendingCaseCount(index, oldCount + delta)
end

local function commitPendingToCart(productIndex)
    local index = ensureIntegerIndex(productIndex, "commitPendingToCart.productIndex")
    if index == nil then
        return
    end
    local pendingCount = state.pendingCaseCountByProduct[index] or 1
    local oldCartCount = state.cartCaseCountByProduct[index] or 0
    state.cartCaseCountByProduct[index] = oldCartCount + pendingCount
    state.pendingCaseCountByProduct[index] = 1
end

local function setCartCaseCount(productIndex, targetCount)
    local index = ensureIntegerIndex(productIndex, "setCartCaseCount.productIndex")
    if index == nil then
        return
    end
    local safeCount = clamp(targetCount, 0, MAX_AMOUNT_PER_PRODUCT)
    state.cartCaseCountByProduct[index] = safeCount
end

local function changeCartCaseCount(productIndex, delta)
    local index = ensureIntegerIndex(productIndex, "changeCartCaseCount.productIndex")
    if index == nil then
        return
    end
    local oldCount = state.cartCaseCountByProduct[index] or 0
    setCartCaseCount(index, oldCount + delta)
end

local function clearCart()
    for productIndex = 1, PRODUCT_COUNT do
        local index = ensureIntegerIndex(productIndex, "clearCart.loopIndex")
        if index ~= nil then
            state.cartCaseCountByProduct[index] = 0
        end
    end
end

local function getCurrentTotalPrice()
    local totalPrice = 0
    for productIndex = 1, PRODUCT_COUNT do
        local index = ensureIntegerIndex(productIndex, "getCurrentTotalPrice.loopIndex")
        if index ~= nil then
            local cartCaseCount = state.cartCaseCountByProduct[index] or 0
            if cartCaseCount > 0 then
                totalPrice = totalPrice + (getCasePrice(index) * cartCaseCount)
            end
        end
    end
    return totalPrice
end

local function checkout()
    GlobalAPI.show_tips("提交订单，总价: " .. formatMoney(getCurrentTotalPrice()), 3.0)
    clearCart()
end

local function getProductIndexBySlot(line, col)
    -- 左侧二维槽位(line, col) -> 商品下标（1-based）。
    local safeLine = ensureIntegerIndex(line, "getProductIndexBySlot.line")
    local safeCol = ensureIntegerIndex(col, "getProductIndexBySlot.col")
    if safeLine == nil or safeCol == nil then
        traceIndex(string.format("getProductIndexBySlot 失败: line=%s col=%s", tostring(safeLine), tostring(safeCol)))
        return nil
    end
    if safeLine < 1 or safeCol < 1 or safeCol > GRID_ITEMS_PER_LINE then
        return nil
    end

    local productIndex = (safeLine - 1) * GRID_ITEMS_PER_LINE + safeCol
    if productIndex < 1 or productIndex > PRODUCT_COUNT then
        traceIndex(string.format("getProductIndexBySlot 越界: line=%d col=%d productIndex=%d PRODUCT_COUNT=%d", safeLine, safeCol, productIndex, PRODUCT_COUNT))
        return nil
    end

    return productIndex
end

local function getProductIndexByCartRow(row)
    -- 右侧清单行号 -> 商品下标（依赖最近一次 refreshUI 构建的映射）。
    local rowIndex = ensureIntegerIndex(row, "getProductIndexByCartRow.row")
    if rowIndex == nil then
        traceIndex("getProductIndexByCartRow 失败: row=" .. tostring(row))
        return nil
    end
    return state.cartRowProductIndices[rowIndex]
end

local function bindNodeTouch(nodeName, handler)
    local node = getNode(nodeName)
    if node == nil then
        return
    end

    for _, touchEventType in ipairs(UI_TOUCH_EVENT_TYPES) do
        LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, node, touchEventType }, function(_, _, data)
            -- TODO(UI): UI 节点点击/触摸事件入口。
            handler(data)
        end)
    end
end

local function bindUIEvents()
    -- 事件职责约定：
    -- 左侧 Add/Dec 只改 pending；Purchase 提交到 cart 并重置 pending=1。
    -- 右侧 CartAdd/CartDec 只改 cart。
    -- Clear/Checkout 作用于购物车整体。
    -- 所有事件末尾统一 refreshUI。
    for productIndex = 1, PRODUCT_COUNT do
        local line, col = getProductSlot(productIndex)
        local leftNodes = getLeftGridNodeNames(line, col)

        bindNodeTouch(leftNodes.addButton, function()
            local index = getProductIndexBySlot(line, col)
            if index then
                changePendingCaseCount(index, 1)
                refreshUI("left_add")
            end
        end)

        bindNodeTouch(leftNodes.decButton, function()
            local index = getProductIndexBySlot(line, col)
            if index then
                changePendingCaseCount(index, -1)
                refreshUI("left_dec")
            end
        end)

        bindNodeTouch(leftNodes.purchaseButton, function()
            local index = getProductIndexBySlot(line, col)
            if index then
                commitPendingToCart(index)
                refreshUI("left_purchase")
            end
        end)
    end

    for row = 1, state.activeCartRows do
        local rowIndex = row
        local rightNodes = getRightRowNodeNames(rowIndex)

        bindNodeTouch(rightNodes.addButton, function()
            local productIndex = getProductIndexByCartRow(rowIndex)
            if productIndex then
                changeCartCaseCount(productIndex, 1)
                refreshUI("right_add")
            end
        end)

        bindNodeTouch(rightNodes.decButton, function()
            local productIndex = getProductIndexByCartRow(rowIndex)
            if productIndex then
                changeCartCaseCount(productIndex, -1)
                refreshUI("right_dec")
            end
        end)
    end

    bindNodeTouch(CART_PANEL_NODE_NAMES.purchaseButton, function()
        checkout()
        refreshUI("checkout")
    end)

    bindNodeTouch(CART_PANEL_NODE_NAMES.clearButton, function()
        clearCart()
        refreshUI("clear")
    end)
end

local function detectActiveCartRows()
    -- 按右侧节点是否完整存在，检测实际可用清单行数。
    local count = 0
    for row = 1, MAX_CART_ROWS do
        local nodeNames = getRightRowNodeNames(row)
        if hasNodeName(nodeNames.root)
            and hasNodeName(nodeNames.itemName)
            and hasNodeName(nodeNames.subTotal)
            and hasNodeName(nodeNames.amount)
            and hasNodeName(nodeNames.addButton)
            and hasNodeName(nodeNames.decButton) then
            count = count + 1
        end
    end
    return count
end

local function initializeState()
    -- 初始化默认状态：左侧待购 1 箱，右侧购物车 0 箱。
    for productIndex = 1, PRODUCT_COUNT do
        local index = ensureIntegerIndex(productIndex, "initializeState.loopIndex")
        if index ~= nil then
            state.pendingCaseCountByProduct[index] = 1
            state.cartCaseCountByProduct[index] = 0
        end
    end
    state.activeCartRows = detectActiveCartRows()
    state.cartRowProductIndices = {}
end

function ShoppingCartUI.init()
    if state.initialized then
        return
    end

    initializeState()
    bindUIEvents()
    renderRightStaticText()
    refreshUI("init")
    state.initialized = true
end

return ShoppingCartUI
