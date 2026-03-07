local MathUtils = {}

---打乱表元素顺序
---@param elements table 元素表
function MathUtils.shuffleTable(elements)
	if type(elements) ~= "table" then
		GlobalAPI.warning("MathUtils.shuffleTable: elements must be a table")
		return
	end

	local n = #elements
	if n <= 1 then
		GlobalAPI.warning("MathUtils.shuffleTable: elements length <= 1, no shuffle needed")
		return
	end

	local count = 0
	for _ in ipairs(elements) do
		count = count + 1
	end
	if count ~= n then
		GlobalAPI.warning("MathUtils.shuffleTable: elements is not a contiguous array (1..n)")
	end

	for i = n, 2, -1 do
		local j = MathUtils.randint(1, i)
		elements[i], elements[j] = elements[j], elements[i]
	end
end

---@param center Vector3
---@param radius Fixed
---@param count integer
---@param startAngle Fixed|nil
---@return table
function MathUtils.getPointsOnCircle(center, radius, count, startAngle)
	assert(count and count >= 1, "count must be >= 1")
	startAngle = startAngle or math.tofixed(0)

	local points = {}
	local step = (2 * math.pi) / count

	for i = 0, count - 1 do
		local theta = startAngle + step * i
		local x = center.x + math.cos(theta) * radius
		local z = center.z + math.sin(theta) * radius
		points[i + 1] = math.Vector3(x, center.y, z)
	end
	return points
end

function MathUtils.randint(min, max)
    -- return min + math.tointeger(LuaAPI.rand() * (max - min))
	return GameAPI.random_int(min, max)
end

--返回指定范围内的不重复整数数组
---@param count integer 数量
---@param max? integer 最大值
---@return table
function MathUtils.randIntArr(count, max)
	max = max or count
	assert(count <= max, "count must be less than or equal to max")

	local allInts = {}
	for i = 1, max do
		table.insert(allInts, i)
	end

	MathUtils.shuffleTable(allInts)

	local result = {}
	for i = 1, count do
		table.insert(result, allInts[i])
	end

	return result
end

function MathUtils.randCirclePoint(center, minRange, maxRange)
	local radian = LuaAPI.rand() * math.pi * 2
	local distance = minRange + math.sqrt(LuaAPI.rand()) * (maxRange - minRange)
	local offset = math.Vector3(math.cos(radian) * distance, 2, math.sin(radian) * distance)
	return center + offset
end

function MathUtils.randRectanglePoint(center, minOffset, maxOffset)
	local x = minOffset.x + LuaAPI.rand() * (maxOffset.x - minOffset.x)
	local y = minOffset.y + LuaAPI.rand() * (maxOffset.y - minOffset.y)
	local z = minOffset.z + LuaAPI.rand() * (maxOffset.z - minOffset.z)
	return center + math.Vector3(x, y, z)
end

function MathUtils.randomChoice(items)
	return items[MathUtils.randint(1, #items)]
end

function MathUtils.weightedRandomChoice(items, weights)
	-- 计算权重总和
	local totalWeight = 0
	for _, weight in ipairs(weights) do
		totalWeight = totalWeight + weight
	end

	-- 生成随机数
	local randomValue = LuaAPI.rand() * totalWeight

	-- 选择项目
	local currentWeight = 0
	for i, item in ipairs(items) do
		currentWeight = currentWeight + weights[i]
		if randomValue <= currentWeight then
			return i, item
		end
	end
	-- 理论上不会到达这里
	return #items, items[#items]
end

return MathUtils
