local TestDestroyedUnitHandleProbe = {}

local TAG = "[TestDestroyedUnitHandleProbe]"
local Timer = require("Utils.Timer")
local UINodes = require("Data.UINodes")
local Prefab = require("Data.Prefab")

local DEBUG_LOG_ENABLED = false -- 排障日志开关（默认关闭）
local CREATE_FORWARD_DISTANCE = 3.0 -- 测试单位生成到角色前方距离（单位：米）
local DELAY_OBSERVE_SEC = 0.2 -- 销毁后延迟观测时长（单位：秒）
local TIPS_DURATION_SUCCESS = 2.0 -- 成功提示时长（GlobalAPI.show_tips _duration，单位：秒）
local TIPS_DURATION_ERROR = 3.0 -- 失败提示时长（GlobalAPI.show_tips _duration，单位：秒）
local PROBE_COMPARE_MODE = "both" -- 观测模式（destroy|control|both）
local CONTROL_AUTO_CLEANUP = true -- 对照组观测完成后是否自动销毁测试单位
local ENABLE_DESTROY_EVENT_PROBE = true -- 销毁事件观测开关（仅 destroy_group）
local PROBE_UNIT_KEY = Prefab.unit.Attachment -- 观测测试单位（GameAPI.create_unit_with_scale _u_key）
local PROBE_UNIT_SCALE = math.Vector3(0.1, 0.1, 0.1) -- 观测测试单位缩放（GameAPI.create_unit_with_scale _scale）
local PROBE_ROTATION_OFFSET = math.Quaternion(0.0, 0.0, 0.0) -- 观测测试单位旋转偏移（GameAPI.create_unit_with_scale _rotation）

local inited = false
local probeSessionId = 0
local anyObstacleDestroyRegistered = false
local activeGlobalEventReports = dict()

local function debugLog(...)
    if not DEBUG_LOG_ENABLED then
        return
    end
    print(TAG, ...)
end

---@param methodName string
---@param invoker fun(): any
---@return table
local function captureMethodResult(methodName, invoker)
    local ok, result = pcall(invoker)
    local record = {
        method = methodName,
        ok = ok,
        retType = nil,
        retText = nil,
        errType = nil,
        errText = nil,
    }

    if ok then
        record.retType = type(result)
        record.retText = tostring(result)
    else
        record.errType = type(result)
        record.errText = tostring(result)
    end

    return record
end

---@param stageName string
---@param unit Unit
---@return table
local function captureUnitObservation(stageName, unit)
    return {
        stage = stageName,
        records = {
            captureMethodResult("get_position", function()
                return unit.get_position()
            end),
            captureMethodResult("get_orientation", function()
                return unit.get_orientation()
            end),
            captureMethodResult("get_local_direction(FORWARD)", function()
                return unit.get_local_direction(Enums.DirectionType.FORWARD)
            end),
        },
    }
end

---@param sessionId integer
---@param report table
local function printProbeReport(sessionId, report)
    print(TAG, "probe report begin, session:", sessionId, "group:", report.groupName, "action:", report.actionName)
    print(
        TAG,
        "action call result, ok:",
        report.actionCallOk,
        "errType:",
        report.actionCallErrType,
        "err:",
        report.actionCallErrText
    )

    for _, observation in ipairs(report.observations) do
        print(TAG, "observation stage:", observation.stage)
        for _, record in ipairs(observation.records) do
            print(
                TAG,
                "method:",
                record.method,
                "ok:",
                record.ok,
                "retType:",
                record.retType,
                "ret:",
                record.retText,
                "errType:",
                record.errType,
                "err:",
                record.errText
            )
        end
    end
    if report.eventProbe ~= nil then
        print(
            TAG,
            "destroy event summary, lifeentity:",
            report.eventProbe.lifeentityDestroyHit,
            "obstacle:",
            report.eventProbe.obstacleDestroyHit,
            "anyObstacle:",
            report.eventProbe.anyObstacleDestroyHit,
            "detailCount:",
            #report.eventProbe.details
        )
        for _, eventDetail in ipairs(report.eventProbe.details) do
            print(
                TAG,
                "destroy event detail, source:",
                eventDetail.source,
                "event:",
                eventDetail.eventName,
                "rawType:",
                eventDetail.rawEventNameType,
                "unitMatched:",
                eventDetail.unitMatched
            )
        end
    end
    print(TAG, "probe report end, session:", sessionId, "group:", report.groupName)
end

---@param report table
---@param source string
---@param eventName any
---@param actor Actor|nil
---@param data table|nil
---@param probeUnit Unit
local function recordDestroyEvent(report, source, eventName, actor, data, probeUnit)
    if report.eventProbe == nil then
        return
    end

    local eventNameText = nil
    if type(eventName) == "string" then
        eventNameText = eventName
    elseif type(eventName) == "table" then
        local firstName = eventName[1]
        if type(firstName) == "string" then
            eventNameText = firstName
        end
    end

    local eventUnit = nil
    if data ~= nil then
        eventUnit = data.unit
    end

    if eventUnit == nil and actor ~= nil and source == "global" then
        eventUnit = actor
    end

    local unitMatched = source == "unit" or eventUnit == probeUnit
    report.eventProbe.details[#report.eventProbe.details + 1] = {
        source = source,
        eventName = eventNameText,
        rawEventName = eventName,
        rawEventNameType = type(eventName),
        unitMatched = unitMatched,
    }

    if source == "unit" and (eventNameText == EVENT.SPEC_LIFEENTITY_DESTROY or eventNameText == "ET_SPEC_LIFEENTITY_DESTROY") then
        report.eventProbe.lifeentityDestroyHit = true
    end
    if source == "unit" and (eventNameText == EVENT.SPEC_OBSTACLE_DESTROY or eventNameText == "ET_SPEC_OBSTACLE_DESTROY") then
        report.eventProbe.obstacleDestroyHit = true
    end
    if source == "global" and (eventNameText == EVENT.ANY_OBSTACLE_DESTROY or eventNameText == "ET_ANY_OBSTACLE_DESTROY") and unitMatched then
        report.eventProbe.anyObstacleDestroyHit = true
    end
end

---@param report table
---@param probeUnit Unit
local function registerDestroyEventProbe(report, probeUnit)
    LuaAPI.unit_register_trigger_event(probeUnit, { EVENT.SPEC_LIFEENTITY_DESTROY }, function(eventName, actor, data)
        recordDestroyEvent(report, "unit", eventName, actor, data, probeUnit)
        debugLog("unit destroy event(lifeentity) hit, actor:", actor, "data:", data)
    end)

    LuaAPI.unit_register_trigger_event(probeUnit, { EVENT.SPEC_OBSTACLE_DESTROY }, function(eventName, actor, data)
        recordDestroyEvent(report, "unit", eventName, actor, data, probeUnit)
        debugLog("unit destroy event(obstacle) hit, actor:", actor, "data:", data)
    end)

    if not anyObstacleDestroyRegistered then
        anyObstacleDestroyRegistered = true
        LuaAPI.global_register_trigger_event({ EVENT.ANY_OBSTACLE_DESTROY }, function(eventName, actor, data)
            local eventUnit = nil
            if data ~= nil then
                eventUnit = data.unit
            end
            if eventUnit ~= nil then
                local eventReport = activeGlobalEventReports:get(eventUnit)
                if eventReport ~= nil then
                    recordDestroyEvent(eventReport, "global", eventName, actor, data, eventUnit)
                end
            end
            debugLog("global destroy event(any obstacle) hit, actor:", actor, "data:", data, "eventUnit:", eventUnit)
        end)
    end

    activeGlobalEventReports:set(probeUnit, report)
end

---@param role Role|nil
---@return Unit|nil
local function createProbeUnitInFront(role)
    if role == nil then
        print(TAG, "missing role for probe")
        GlobalAPI.show_tips("角色信息缺失，无法执行观测", TIPS_DURATION_ERROR)
        return nil
    end

    local ctrlUnit = role.get_ctrl_unit()
    if ctrlUnit == nil then
        print(TAG, "missing ctrl unit for probe")
        GlobalAPI.show_tips("角色控制单位缺失，无法执行观测", TIPS_DURATION_ERROR)
        return nil
    end

    if type(PROBE_UNIT_KEY) ~= "number" then
        print(TAG, "invalid probe unit key:", PROBE_UNIT_KEY, "type:", type(PROBE_UNIT_KEY))
        GlobalAPI.show_tips("测试单位配置错误，无法执行观测", TIPS_DURATION_ERROR)
        return nil
    end

    local spawnPosition = ctrlUnit.get_position()
        + ctrlUnit.get_local_direction(Enums.DirectionType.FORWARD) * CREATE_FORWARD_DISTANCE
    local spawnRotation = ctrlUnit.get_orientation() * PROBE_ROTATION_OFFSET
    local probeUnit = GameAPI.create_unit_with_scale(PROBE_UNIT_KEY, spawnPosition, spawnRotation, PROBE_UNIT_SCALE)
    if probeUnit == nil then
        print(TAG, "create probe unit failed")
        GlobalAPI.show_tips("测试单位创建失败", TIPS_DURATION_ERROR)
        return nil
    end

    debugLog("create probe unit success:", probeUnit)
    return probeUnit
end

---@param role Role|nil
---@param groupName string
---@param shouldDestroy boolean
local function runSingleProbe(role, groupName, shouldDestroy)
    local probeUnit = createProbeUnitInFront(role)
    if probeUnit == nil then
        return
    end

    probeSessionId = probeSessionId + 1
    local sessionId = probeSessionId
    local report = {
        groupName = groupName,
        actionName = shouldDestroy and "destroy_unit" or "no_destroy",
        actionCallOk = not shouldDestroy,
        actionCallErrType = nil,
        actionCallErrText = nil,
        observations = {},
        eventProbe = nil,
    }

    if ENABLE_DESTROY_EVENT_PROBE and shouldDestroy then
        report.eventProbe = {
            lifeentityDestroyHit = false,
            obstacleDestroyHit = false,
            anyObstacleDestroyHit = false,
            details = {},
        }
        registerDestroyEventProbe(report, probeUnit)
    end

    report.observations[#report.observations + 1] = captureUnitObservation("before_action", probeUnit)

    if shouldDestroy then
        local destroyCallOk, destroyCallResult = pcall(function()
            GameAPI.destroy_unit(probeUnit)
        end)
        report.actionCallOk = destroyCallOk
        if not destroyCallOk then
            report.actionCallErrType = type(destroyCallResult)
            report.actionCallErrText = tostring(destroyCallResult)
        end
    end

    report.observations[#report.observations + 1] = captureUnitObservation("after_action_immediate", probeUnit)

    local delayTimer = Timer.new(DELAY_OBSERVE_SEC, false)
    delayTimer:setTimeEndCb(function()
        report.observations[#report.observations + 1] = captureUnitObservation("after_action_delayed", probeUnit)
        printProbeReport(sessionId, report)
        if report.eventProbe ~= nil then
            activeGlobalEventReports:set(probeUnit, nil)
        end
        if not shouldDestroy and CONTROL_AUTO_CLEANUP then
            pcall(function()
                GameAPI.destroy_unit(probeUnit)
            end)
        end
        GlobalAPI.show_tips("句柄观测完成（" .. groupName .. "）", TIPS_DURATION_SUCCESS)
    end)
    delayTimer:start()
end

---@param role Role|nil
local function runHandleProbe(role)
    if PROBE_COMPARE_MODE == "destroy" then
        runSingleProbe(role, "destroy_group", true)
        return
    end

    if PROBE_COMPARE_MODE == "control" then
        runSingleProbe(role, "control_group", false)
        return
    end

    if PROBE_COMPARE_MODE == "both" then
        runSingleProbe(role, "destroy_group", true)
        runSingleProbe(role, "control_group", false)
        return
    end

    print(TAG, "invalid PROBE_COMPARE_MODE:", PROBE_COMPARE_MODE)
    GlobalAPI.show_tips("观测模式配置错误", TIPS_DURATION_ERROR)
end

function TestDestroyedUnitHandleProbe.init()
    if inited then
        return
    end
    inited = true

    local shelfNode = UINodes.TestShelfCreate
    if shelfNode == nil then
        print(TAG, "missing ui node: TestShelfCreate")
        GlobalAPI.show_tips("缺少节点 TestShelfCreate", TIPS_DURATION_ERROR)
        return
    end

    LuaAPI.global_register_trigger_event({ EVENT.EUI_NODE_TOUCH_EVENT, shelfNode, 1 }, function(_, actor, data)
        if data == nil then
            print(TAG, "touch data nil: TestShelfCreate", actor)
            return
        end
        runHandleProbe(data.role)
    end)
end

return TestDestroyedUnitHandleProbe
