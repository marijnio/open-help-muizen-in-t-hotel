-- Virtual 640x480 canvas & safe-area-aware aspect-preserving viewport.

local Viewport = {
    VIRTUAL_W = 640,
    VIRTUAL_H = 480,
    filter = "linear",
    canvas = nil,
    scale = 1,
    offsetX = 0,
    offsetY = 0,
}

function Viewport.init()
    Viewport.canvas = love.graphics.newCanvas(Viewport.VIRTUAL_W, Viewport.VIRTUAL_H)
    Viewport.canvas:setFilter(Viewport.filter, Viewport.filter)
    Viewport.recalculate()
end

function Viewport.recalculate()
    local sx, sy, sw, sh = 0, 0, love.graphics.getDimensions()
    if love.window.getSafeArea then
        local ax, ay, aw, ah = love.window.getSafeArea()
        if aw and ah and aw > 0 and ah > 0 then
            sx, sy, sw, sh = ax, ay, aw, ah
        end
    end
    if not sw or not sh or sw <= 0 or sh <= 0 then
        return
    end

    local scaleX = sw / Viewport.VIRTUAL_W
    local scaleY = sh / Viewport.VIRTUAL_H
    Viewport.scale = math.min(scaleX, scaleY)
    Viewport.offsetX = sx + (sw - Viewport.VIRTUAL_W * Viewport.scale) * 0.5
    Viewport.offsetY = sy + (sh - Viewport.VIRTUAL_H * Viewport.scale) * 0.5
end

function Viewport.setFilter(mode)
    Viewport.filter = mode
    if Viewport.canvas then
        Viewport.canvas:setFilter(mode, mode)
    end
end

function Viewport.toggleFilter()
    local nextMode = (Viewport.filter == "linear") and "nearest" or "linear"
    Viewport.setFilter(nextMode)
    return nextMode
end

function Viewport.getFilter()
    return Viewport.filter
end

function Viewport.beginDraw()
    Viewport.recalculate()
    love.graphics.setCanvas(Viewport.canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
end

function Viewport.endDraw()
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        Viewport.canvas,
        Viewport.offsetX,
        Viewport.offsetY,
        0,
        Viewport.scale,
        Viewport.scale
    )
end

function Viewport.screenToVirtual(sx, sy)
    if not Viewport.scale or Viewport.scale <= 0 then
        return 0, 0, false
    end
    local vx = (sx - Viewport.offsetX) / Viewport.scale
    local vy = (sy - Viewport.offsetY) / Viewport.scale
    local inside = vx >= 0 and vx < Viewport.VIRTUAL_W and vy >= 0 and vy < Viewport.VIRTUAL_H
    return vx, vy, inside
end

return Viewport
