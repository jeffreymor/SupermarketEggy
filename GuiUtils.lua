local UIUtils = {}
local ColorUtils = require("Utils.ColorUtils")

local GlobalNodeVisibleStatus = {} --全局节点可见状态，键为节点，值为true/false

---@param adjustFuncName string 调整函数名
---@param ... any 调整函数参数
local function adjustAllRoleGui(adjustFuncName, ...)
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        role[adjustFuncName](...)
    end
end

---@param node ENode 节点
function UIUtils.showNode(node)
    adjustAllRoleGui("set_node_visible", node, true)
    GlobalNodeVisibleStatus[node] = true
end

---@param node ENode 节点
function UIUtils.hideNode(node)
    adjustAllRoleGui("set_node_visible", node, false)
    GlobalNodeVisibleStatus[node] = false
end

---不可靠，只有设置过可见状态的节点才有正确结果
---@param node ENode
---@return boolean
function UIUtils.isNodeGlobalVisible(node)
    return GlobalNodeVisibleStatus[node] == true
end

---@param node ENode 节点
function UIUtils.setLabelText(node, text)
    adjustAllRoleGui("set_label_text", node, tostring(text))
end

---@param node EImage 节点
---@param color string 颜色字符串，支持 "#RRGGBB" 或 "RRGGBB" 格式
---@param transitionTime? Fixed 过渡时间，单位秒
function UIUtils.setImageColor(node, color, transitionTime)
    adjustAllRoleGui("set_image_color", node, ColorUtils.strToColorWithHash(color), transitionTime or math.tofixed(0))
end

---@param node EImage
---@param imageId ImageKey
function UIUtils.setImage(node, imageId)
    adjustAllRoleGui("set_image_texture_by_key_with_auto_resize", node, imageId, false)
end

---@param role Role 角色
---@param node EImage 节点
---@param color string 颜色字符串，支持 "#RRGGBB" 或 "RRGGBB" 格式
---@param transitionTime? Fixed 过渡时间，单位秒
function UIUtils.setPlayerImageColor(role, node, color, transitionTime)
    role.set_image_color(node, ColorUtils.strToColorWithHash(color), transitionTime or math.tofixed(0))
end

---@param role Role 角色
---@param node ENode 节点
---@param text string 显示文本
function UIUtils.setPlayerLabelText(role, node, text)
    role.set_label_text(node, tostring(text))
end

---@param role Role 角色
---@param node ENode 节点
function UIUtils.showPlayerNode(role, node)
    role.set_node_visible(node, true)
end

---@param role Role 角色
---@param node ENode 节点
function UIUtils.hidePlayerNode(role, node)
    role.set_node_visible(node, false)
end

return UIUtils
