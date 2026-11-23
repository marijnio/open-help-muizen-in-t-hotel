-- Touch-safe hardware cursor wrapper.

local Cursor = {
    supported = false,
    cursors = {},
    visible = true,
}

function Cursor.init()
    Cursor.supported = love.mouse and love.mouse.isCursorSupported and love.mouse.isCursorSupported() or false
    if Cursor.supported then
        Cursor.cursors.arrow = love.mouse.getSystemCursor("arrow")
        Cursor.cursors.hand = love.mouse.getSystemCursor("hand")
    end
end

function Cursor.setSystem(name)
    if not Cursor.supported then return end
    local c = Cursor.cursors[name]
    if c then
        love.mouse.setCursor(c)
    end
end

function Cursor.setVisible(vis)
    Cursor.visible = vis and true or false
    if Cursor.supported and love.mouse.setVisible then
        love.mouse.setVisible(Cursor.visible)
    end
end

function Cursor.reset()
    Cursor.setVisible(true)
    Cursor.setSystem("arrow")
end

return Cursor
