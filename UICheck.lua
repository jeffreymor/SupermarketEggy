local UINodes = require("Data.UINodes")

function tonumber(str)
    if str == nil then
        return nil
    end

    local valueType = type(str)
    if valueType == "number" then
        if math and math.tointeger then
            local intValue = math.tointeger(str)
            if intValue ~= nil then
                return intValue
            end
        end
        return str
    end

    if valueType ~= "string" then
        return nil
    end

    if str == "" then
        return nil
    end

    if math and math.tointeger then
        local intValue = math.tointeger(str)
        if intValue ~= nil then
            return intValue
        end
    end

    local index = 1
    local length = #str
    local sign = 1

    local first = string.byte(str, 1)
    if first == 45 then
        sign = -1
        index = 2
    elseif first == 43 then
        index = 2
    end

    if index > length then
        return nil
    end

    local number = 0
    for i = index, length do
        local b = string.byte(str, i)
        if b < 48 or b > 57 then
            return nil
        end
        number = number * 10 + (b - 48)
    end

    return sign * number
end

function warn(content)
    GlobalAPI.warning(content)
end

local ITEMS_PER_LINE = 2

local ITEM_CHILD_PREFIXES = {
    "ItemInfoFrame",
    "ItemName",
    "ShelfImage",
    "ItemImage",
    "AmountFrame",
    "AmountLabel",
    "PurchaseInfo",
    "UnitLabel",
    "UnitPrice",
    "AmountAdjustFrame",
    "PurchaseAmountLabel",
    "DecBtn",
    "AddBtn",
    "PurchaseBtn",
    "CasePriceLabel",
}

local VALID_FIXED_NODES = {
    MainFrame = true,
    ShopFrame = true,
    ShopList = true,
}

local VALID_PREFIXES = {
    "MainFrame",
    "ShopFrame",
    "ShopList",
    "LineFrame",
    "LineItem",
    "ItemInfoFrame",
    "ItemName",
    "ShelfImage",
    "ItemImage",
    "AmountFrame",
    "AmountLabel",
    "PurchaseInfo",
    "UnitLabel",
    "UnitPrice",
    "AmountAdjustFrame",
    "PurchaseAmountLabel",
    "DecBtn",
    "AddBtn",
    "PurchaseBtn",
    "CasePriceLabel",
}

local function hasNode(nodes, name)
    return nodes[name] ~= nil
end

local function sortedKeys(map)
    local result = {}
    for k, _ in pairs(map) do
        table.insert(result, k)
    end
    table.sort(result)
    return result
end

local function parseLineFrame(name)
    local line = string.match(name, "^LineFrame_(%d+)$")
    if line then
        return tonumber(line)
    end
    return nil
end

local function parseLineItem(name)
    local line, col = string.match(name, "^LineItem_(%d+)_(%d+)$")
    if line and col then
        return tonumber(line), tonumber(col)
    end
    return nil, nil
end

local function parseItemChild(name)
    local prefix, line, col = string.match(name, "^(.-)_(%d+)_(%d+)$")
    if prefix and line and col then
        return prefix, tonumber(line), tonumber(col)
    end
    return nil, nil, nil
end

local function getLineFrameIndices(nodes)
    local set = {}
    local maxLine = 0

    for nodeName, _ in pairs(nodes) do
        local line = parseLineFrame(nodeName)
        if line then
            set[line] = true
            if line > maxLine then
                maxLine = line
            end
        end
    end

    return set, maxLine
end

local function buildExpectedNodeSet(maxLine, itemsPerLine)
    local expected = {}

    expected["MainFrame"] = true
    expected["ShopFrame"] = true
    expected["ShopList"] = true

    for line = 1, maxLine do
        expected["LineFrame_" .. line] = true

        for col = 1, itemsPerLine do
            local suffix = string.format("%d_%d", line, col)

            expected["LineItem_" .. suffix] = true

            expected["ItemInfoFrame_" .. suffix] = true
            expected["ItemName_" .. suffix] = true
            expected["ShelfImage_" .. suffix] = true
            expected["ItemImage_" .. suffix] = true
            expected["AmountFrame_" .. suffix] = true
            expected["AmountLabel_" .. suffix] = true

            expected["PurchaseInfo_" .. suffix] = true
            expected["UnitLabel_" .. suffix] = true
            expected["UnitPrice_" .. suffix] = true
            expected["AmountAdjustFrame_" .. suffix] = true
            expected["PurchaseAmountLabel_" .. suffix] = true
            expected["DecBtn_" .. suffix] = true
            expected["AddBtn_" .. suffix] = true
            expected["PurchaseBtn_" .. suffix] = true
            expected["CasePriceLabel_" .. suffix] = true
        end
    end

    return expected
end

local function getClosestPrefix(name)
    local rawPrefix = string.match(name, "^(.-)_%d+_%d+$")
        or string.match(name, "^(.-)_%d+$")
        or name

    for _, valid in ipairs(VALID_PREFIXES) do
        if rawPrefix == valid then
            return valid
        end
    end

    local rawLower = string.lower(rawPrefix)
    for _, valid in ipairs(VALID_PREFIXES) do
        if rawLower == string.lower(valid) then
            return valid
        end
    end

    for _, valid in ipairs(VALID_PREFIXES) do
        if string.find(rawLower, string.lower(valid), 1, true) then
            return valid
        end
    end

    return nil
end

local function validateUINodes(nodes, itemsPerLine)
    local report = {
        maxLine = 0,
        expectedCount = 0,
        actualCount = 0,

        missing = {},
        unexpected = {},
        lineFrameGaps = {},
        orphanNodes = {},
        invalidLineItemColumns = {},

        ok = false,
    }

    local lineFrameSet, maxLine = getLineFrameIndices(nodes)
    report.maxLine = maxLine

    for _, _ in pairs(nodes) do
        report.actualCount = report.actualCount + 1
    end

    if maxLine == 0 then
        table.insert(report.missing, "LineFrame_1 及后续行节点")
        return report
    end

    -- 1. LineFrame 连续性检查
    for line = 1, maxLine do
        if not lineFrameSet[line] then
            table.insert(report.lineFrameGaps, "LineFrame_" .. line)
        end
    end

    -- 2. 生成期望集合并做缺失检查
    local expectedSet = buildExpectedNodeSet(maxLine, itemsPerLine)

    for _, _ in pairs(expectedSet) do
        report.expectedCount = report.expectedCount + 1
    end

    for expectedName, _ in pairs(expectedSet) do
        if not hasNode(nodes, expectedName) then
            table.insert(report.missing, expectedName)
        end
    end

    -- 3. 多余 / 错名检查
    for actualName, _ in pairs(nodes) do
        if not expectedSet[actualName] then
            table.insert(report.unexpected, actualName)
        end
    end

    -- 4. 孤儿节点 / 越界列检查
    for actualName, _ in pairs(nodes) do
        local line = parseLineFrame(actualName)
        if line then
            -- LineFrame 已在前面检查连续性，这里不用处理
        else
            local itemLine, itemCol = parseLineItem(actualName)
            if itemLine and itemCol then
                if itemCol < 1 or itemCol > itemsPerLine then
                    table.insert(report.invalidLineItemColumns, actualName)
                end

                if not hasNode(nodes, "LineFrame_" .. itemLine) then
                    table.insert(report.orphanNodes, actualName .. "    (缺少父节点: LineFrame_" .. itemLine .. ")")
                end
            else
                local prefix, childLine, childCol = parseItemChild(actualName)
                if prefix and childLine and childCol then
                    local isKnownChildPrefix = false
                    for _, validPrefix in ipairs(ITEM_CHILD_PREFIXES) do
                        if prefix == validPrefix then
                            isKnownChildPrefix = true
                            break
                        end
                    end

                    if isKnownChildPrefix then
                        if childCol < 1 or childCol > itemsPerLine then
                            table.insert(report.invalidLineItemColumns, actualName)
                        end

                        local parentLineFrame = "LineFrame_" .. childLine
                        local parentLineItem = string.format("LineItem_%d_%d", childLine, childCol)

                        if not hasNode(nodes, parentLineFrame) then
                            table.insert(report.orphanNodes, actualName .. "    (缺少父级行: " .. parentLineFrame .. ")")
                        end

                        if not hasNode(nodes, parentLineItem) then
                            table.insert(report.orphanNodes, actualName .. "    (缺少父级项: " .. parentLineItem .. ")")
                        end
                    end
                end
            end
        end
    end

    table.sort(report.missing)
    table.sort(report.unexpected)
    table.sort(report.lineFrameGaps)
    table.sort(report.orphanNodes)
    table.sort(report.invalidLineItemColumns)

    report.ok =
        #report.missing == 0
        and #report.unexpected == 0
        and #report.lineFrameGaps == 0
        and #report.orphanNodes == 0
        and #report.invalidLineItemColumns == 0

    return report
end

local function printNameList(title, list, useHint)
    if #list == 0 then
        return
    end

    warn("---- " .. title .. " ----")
    for _, name in ipairs(list) do
        if useHint then
            local hint = getClosestPrefix(name)
            if hint then
                warn(string.format("%s    (疑似相关前缀: %s)", name, hint))
            else
                warn(name)
            end
        else
            warn(name)
        end
    end
end

local function printReport(report)
    print("===== UI Nodes 校验报告 =====")
    print("扫描到的最大 LineFrame 下标:", report.maxLine)
    print("期望节点数:", report.expectedCount)
    print("实际节点数:", report.actualCount)
    print("缺失节点数:", #report.missing)
    print("多余/错名节点数:", #report.unexpected)
    print("LineFrame 断档数:", #report.lineFrameGaps)
    print("孤儿节点数:", #report.orphanNodes)
    print("非法列号节点数:", #report.invalidLineItemColumns)

    if report.ok then
        print("结果: 校验通过")
        return
    end

    print("结果: 校验失败")

    printNameList("缺失节点", report.missing, false)
    printNameList("多余/错名节点", report.unexpected, true)
    printNameList("LineFrame 不连续", report.lineFrameGaps, false)
    printNameList("孤儿节点", report.orphanNodes, false)
    printNameList("非法列号节点", report.invalidLineItemColumns, false)
end

local report = validateUINodes(UINodes, ITEMS_PER_LINE)
printReport(report)
