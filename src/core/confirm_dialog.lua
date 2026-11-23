-- Reusable modal confirmation dialog overlay.

local Hotzone = require("src.core.hotzone")
local Cursor = require("src.core.cursor")

local ConfirmDialog = {}

function ConfirmDialog:enter(params)
    self.title = params.title or "Bevestigen"
    self.message = params.message or ""
    self.buttons = params.buttons or {
        { label = "Ja", key = "return", action = params.onConfirm },
        { label = "Nee", key = "escape", action = params.onCancel },
    }
    self.hotzones = Hotzone.new()

    local bw, bh = 130, 36
    local gap = 14
    local count = #self.buttons
    local totalW = count * bw + (count - 1) * gap
    local boxW = math.max(380, totalW + 48)
    local boxH = 160
    self.boxX = math.floor((640 - boxW) * 0.5)
    self.boxY = math.floor((480 - boxH) * 0.5)
    self.boxW = boxW
    self.boxH = boxH

    local startX = math.floor((640 - totalW) * 0.5)
    local btnY = self.boxY + self.boxH - bh - 20
    for i, b in ipairs(self.buttons) do
        local bx = startX + (i - 1) * (bw + gap)
        b._x, b._y, b._w, b._h = bx, btnY, bw, bh
        self.hotzones:add({
            id = "dlg_btn_" .. i,
            x = bx,
            y = btnY,
            w = bw,
            h = bh,
            onClick = function()
                if b.action then b.action() end
            end,
        })
    end
    Cursor.reset()
end

function ConfirmDialog:exit()
    Cursor.reset()
end

function ConfirmDialog:mousemoved(vx, vy)
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function ConfirmDialog:mousepressed(vx, vy, button)
    if button == 1 then
        self.hotzones:click(vx, vy)
    end
end

function ConfirmDialog:keypressed(key)
    for _, b in ipairs(self.buttons) do
        if b.key == key and b.action then
            b.action()
            return true
        end
    end
    return true
end

function ConfirmDialog:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    love.graphics.setColor(0.14, 0.16, 0.22, 0.96)
    love.graphics.rectangle("fill", self.boxX, self.boxY, self.boxW, self.boxH, 10, 10)
    love.graphics.setColor(0.85, 0.72, 0.3, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", self.boxX, self.boxY, self.boxW, self.boxH, 10, 10)

    love.graphics.setColor(1, 0.92, 0.6, 1)
    love.graphics.printf(self.title, self.boxX + 16, self.boxY + 18, self.boxW - 32, "center")

    love.graphics.setColor(0.92, 0.94, 0.96, 1)
    love.graphics.printf(self.message, self.boxX + 20, self.boxY + 50, self.boxW - 40, "center")

    for i, b in ipairs(self.buttons) do
        local isHot = (self.hotzones.hoveredId == "dlg_btn_" .. i)
        if isHot then
            love.graphics.setColor(0.32, 0.52, 0.34, 1)
        else
            love.graphics.setColor(0.22, 0.26, 0.34, 1)
        end
        love.graphics.rectangle("fill", b._x, b._y, b._w, b._h, 6, 6)
        love.graphics.setColor(0.8, 0.85, 0.9, 1)
        love.graphics.rectangle("line", b._x, b._y, b._w, b._h, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(b.label, b._x, b._y + 10, b._w, "center")
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
    end
    love.graphics.pop()
end

return ConfirmDialog
