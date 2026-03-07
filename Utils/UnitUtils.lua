local UnitUtils = {}

local ColorUtils = require("Utils.ColorUtils")

local TAG = "[UnitUtils]"

---设置unit各个染色区颜色
---@param unit Unit 单位
---@param colorHexTable table<integer, string> 染色区颜色表，键为染色区索引，值为颜色hex字符串
function UnitUtils.setUnitColor(unit, colorHexTable)
    for areaIndex, color in pairs(colorHexTable) do
        local targetColor = ColorUtils.strToColorWithHash(color)
        unit.set_paint_area_color(Enums.ColorPaintAreaType["AREA_" .. areaIndex], targetColor)
    end
end



return UnitUtils