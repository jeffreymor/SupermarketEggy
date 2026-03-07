local ColorUtils = {}

local TAG = "[ColorUtils]"

---@param hex string 颜色字符串，支持 "#RRGGBB" 或 "RRGGBB" 格式
---@return Color 颜色
function ColorUtils.strToColorWithHash(hex)
    if hex == nil then
        return ColorUtils.strToColorWithHash("#FFFFFF")
    end
    local s = tostring(hex)
    if s:sub(1, 1) == "#" then
        s = s:sub(2)
    end
    return GlobalAPI.str_to_color(s)
end

return ColorUtils