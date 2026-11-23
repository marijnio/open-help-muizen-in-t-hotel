-- Interactive rectangular hotzone manager with F1 debug overlay.

local Hotzone = {}
Hotzone.__index = Hotzone

function Hotzone.new()
    return setmetatable({
        zones = {},
        hoveredId = nil,
    }, Hotzone)
end

function Hotzone:clear()
    self.zones = {}
    self.hoveredId = nil
end

function Hotzone:add(def)
    -- def = { id, x, y, w, h, label, normalSprite, hoverSprite, onHover, onLeave, onClick, enabled }
    def.enabled = (def.enabled ~= false)
    table.insert(self.zones, def)
    return def
end

function Hotzone:hitTest(vx, vy)
    for i = #self.zones, 1, -1 do
        local z = self.zones[i]
        if z.enabled and vx >= z.x and vx < (z.x + z.w) and vy >= z.y and vy < (z.y + z.h) then
            return z
        end
    end
    return nil
end

function Hotzone:updateHover(vx, vy, isTouchMode)
    if isTouchMode then
        self.hoveredId = nil
        return nil
    end
    local hit = self:hitTest(vx, vy)
    local nextId = hit and hit.id or nil
    if nextId ~= self.hoveredId then
        if self.hoveredId then
            for _, z in ipairs(self.zones) do
                if z.id == self.hoveredId and z.onLeave then
                    z.onLeave(z)
                    break
                end
            end
        end
        self.hoveredId = nextId
        if hit and hit.onHover then
            hit.onHover(hit)
        end
    end
    return hit
end

function Hotzone:click(vx, vy)
    local hit = self:hitTest(vx, vy)
    if hit and hit.onClick then
        hit.onClick(hit, vx, vy)
        return hit
    end
    return nil
end

function Hotzone:drawSprites()
    love.graphics.setColor(1, 1, 1, 1)
    for _, z in ipairs(self.zones) do
        if z.enabled then
            local img = (self.hoveredId == z.id and z.hoverSprite) or z.normalSprite
            if img then
                love.graphics.draw(img, z.x, z.y)
            end
        end
    end
end

function Hotzone:drawDebug(vx, vy)
    love.graphics.push("all")
    for _, z in ipairs(self.zones) do
        local isHot = (self.hoveredId == z.id)
        if not z.enabled then
            love.graphics.setColor(0.5, 0.5, 0.5, 0.4)
        elseif isHot then
            love.graphics.setColor(0.2, 1.0, 0.3, 0.9)
        else
            love.graphics.setColor(1.0, 0.85, 0.1, 0.75)
        end
        love.graphics.rectangle("line", z.x, z.y, z.w, z.h)
        love.graphics.setColor(0, 0, 0, 0.75)
        local txt = tostring(z.id)
        love.graphics.rectangle("fill", z.x + 1, z.y + 1, #txt * 6 + 6, 13)
        love.graphics.setColor(1, 1, 0.4, 1)
        love.graphics.print(txt, z.x + 3, z.y + 1)
    end
    if vx and vy then
        local coord = string.format("vx=%.0f, vy=%.0f", vx, vy)
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 4, 4, #coord * 7 + 10, 18)
        love.graphics.setColor(0.3, 1, 0.5, 1)
        love.graphics.print(coord, 9, 6)
    end
    love.graphics.pop()
end

return Hotzone
