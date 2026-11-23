-- Friendly fallback screen when assets/manifest.lua cannot be located.

local Assets = require("src.core.assets")
local Hotzone = require("src.core.hotzone")
local Cursor = require("src.core.cursor")

local MissingAssets = {}

function MissingAssets:enter()
    Cursor.reset()
    self.hotzones = Hotzone.new()
    self.hotzones:add({
        id = "retry",
        x = 170,
        y = 408,
        w = 140,
        h = 40,
        onClick = function()
            if App.reloadAssets() then
                App.enterInitialScene()
            end
        end,
    })
    self.hotzones:add({
        id = "quit",
        x = 330,
        y = 408,
        w = 140,
        h = 40,
        onClick = function()
            love.event.quit()
        end,
    })
end

function MissingAssets:mousemoved(vx, vy)
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function MissingAssets:mousepressed(vx, vy, button)
    if button == 1 then
        self.hotzones:click(vx, vy)
    end
end

function MissingAssets:keypressed(key)
    if key == "r" then
        if App.reloadAssets() then
            App.enterInitialScene()
        end
        return true
    elseif key == "escape" then
        love.event.quit()
        return true
    end
    return false
end

function MissingAssets:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0.08, 0.10, 0.14, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    love.graphics.setColor(0.95, 0.78, 0.3, 1)
    love.graphics.printf("Spelbestanden (assets) niet gevonden", 30, 26, 580, "center")

    love.graphics.setColor(0.88, 0.9, 0.94, 1)
    love.graphics.printf(
        "Plaats je originele kopie van 'Help! Muizen in 't hotel' in een lokale map en voer het conversiescript uit:",
        36,
        66,
        568,
        "left"
    )

    love.graphics.setColor(0.14, 0.18, 0.24, 1)
    love.graphics.rectangle("fill", 36, 110, 568, 38, 6, 6)
    love.graphics.setColor(0.45, 0.95, 0.6, 1)
    love.graphics.print("python3 tools/convert_assets.py --source <originele-map> --output assets", 48, 122)

    love.graphics.setColor(0.85, 0.88, 0.92, 1)
    love.graphics.print("Gecontroleerde locaties:", 36, 166)

    love.graphics.setColor(0.12, 0.14, 0.19, 1)
    love.graphics.rectangle("fill", 36, 190, 568, 196, 6, 6)
    love.graphics.setColor(0.75, 0.80, 0.86, 1)
    local y = 202
    for _, line in ipairs(Assets.checkedPaths) do
        love.graphics.printf(line, 48, y, 544, "left")
        y = y + 42
    end

    -- Buttons
    for _, btn in ipairs({
        { id = "retry", label = "Opnieuw (R)", x = 170 },
        { id = "quit", label = "Afsluiten (Esc)", x = 330 },
    }) do
        local isHot = (self.hotzones.hoveredId == btn.id)
        love.graphics.setColor(isHot and 0.28 or 0.18, isHot and 0.48 or 0.24, isHot and 0.34 or 0.32, 1)
        love.graphics.rectangle("fill", btn.x, 408, 140, 40, 6, 6)
        love.graphics.setColor(0.7, 0.78, 0.88, 1)
        love.graphics.rectangle("line", btn.x, 408, 140, 40, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(btn.label, btn.x, 421, 140, "center")
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
    end
    love.graphics.pop()
end

return MissingAssets
