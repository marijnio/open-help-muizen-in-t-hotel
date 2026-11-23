-- CD-ROM Launcher: Main Game + Intro + upcoming Bonus Games (Maze & Super Spel).

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local Hotzone = require("src.core.hotzone")
local SceneManager = require("src.core.scene_manager")
local ConfirmDialog = require("src.core.confirm_dialog")

local Launcher = {}

local MENU_ITEMS = {
    { id = "main_game", label = "Help! Muizen in 't Hotel!", sub = "Hoofdspel" },
    { id = "intro",     label = "Introductiefilm bekijken",  sub = "Verhaal (QuickTime)" },
    { id = "doolhof",   label = "Het Muizendoolhof",         sub = "Bonusspel • Doolhof" },
    { id = "superspel", label = "Super Spel",                sub = "Bonusspel • Arcade" },
    { id = "quit",      label = "Afsluiten",                 sub = "Esc" },
}

function Launcher:enter(params)
    Cursor.reset()
    if params and params.keepMusic then
        AudioQueue.stopVo()
    else
        AudioQueue.stopAll()
    end
    self.notice = nil
    self.noticeTimer = 0
    self.hotzones = Hotzone.new()

    local startY = 140
    local btnW, btnH = 340, 46
    local btnX = math.floor((640 - btnW) * 0.5)
    local gap = 10

    for i, item in ipairs(MENU_ITEMS) do
        local by = startY + (i - 1) * (btnH + gap)
        item._x, item._y, item._w, item._h = btnX, by, btnW, btnH
        self.hotzones:add({
            id = item.id,
            x = btnX,
            y = by,
            w = btnW,
            h = btnH,
            onClick = function()
                self:activate(item.id)
            end,
        })
    end

    self.hotzones:add({
        id = "credits",
        x = 532,
        y = 442,
        w = 94,
        h = 28,
        onClick = function()
            SceneManager.switch(App.states.credits)
        end,
    })
end

function Launcher:exit()
    Cursor.reset()
end

function Launcher:activate(id)
    if id == "main_game" then
        SceneManager.switch(App.states.start_menu)
    elseif id == "intro" then
        SceneManager.switch(App.states.intro)
    elseif id == "doolhof" then
        SceneManager.switch(App.states.doolhof)
    elseif id == "superspel" then
        SceneManager.switch(App.states.super_hub, { newGame = true })
    elseif id == "quit" then
        self:promptQuit()
    end
end

function Launcher:promptQuit()
    SceneManager.setOverlay(ConfirmDialog, {
        title = "Spel afsluiten",
        message = "Weet je zeker dat je wilt afsluiten?",
        buttons = {
            { label = "Ja", key = "return", action = function() love.event.quit() end },
            { label = "Nee", key = "escape", action = function() SceneManager.clearOverlay() end },
        },
    })
end

function Launcher:update(dt)
    if self.noticeTimer > 0 then
        self.noticeTimer = self.noticeTimer - dt
        if self.noticeTimer <= 0 then
            self.notice = nil
        end
    end
end

function Launcher:mousemoved(vx, vy)
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function Launcher:mousepressed(vx, vy, button)
    if button == 1 then
        self.hotzones:click(vx, vy)
    end
end

function Launcher:keypressed(key)
    if key == "escape" then
        self:promptQuit()
        return true
    elseif key == "return" or key == "space" then
        self:activate("main_game")
        return true
    end
    return false
end

function Launcher:draw(vx, vy)
    love.graphics.push("all")
    local bg = Assets.getManifestImage("muizen")
    if bg then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(bg, 0, 0)
        love.graphics.setColor(0.04, 0.06, 0.09, 0.72)
        love.graphics.rectangle("fill", 0, 0, 640, 480)
    else
        love.graphics.setColor(0.08, 0.12, 0.14, 1)
        love.graphics.rectangle("fill", 0, 0, 640, 480)
    end

    -- Title banner
    love.graphics.setColor(0.10, 0.14, 0.18, 0.9)
    love.graphics.rectangle("fill", 90, 24, 460, 74, 10, 10)
    love.graphics.setColor(0.45, 0.92, 0.42, 1)
    love.graphics.rectangle("line", 90, 24, 460, 74, 10, 10)

    love.graphics.setColor(0.55, 1.0, 0.45, 1)
    love.graphics.printf("HELP! MUIZEN IN 'T HOTEL!", 90, 38, 460, "center")
    love.graphics.setColor(0.85, 0.90, 0.92, 1)
    love.graphics.printf("Open-Source LÖVE Reïmplementatie • Kies een onderdeel", 90, 64, 460, "center")

    for _, item in ipairs(MENU_ITEMS) do
        local isHot = (self.hotzones.hoveredId == item.id)
        if isHot then
            love.graphics.setColor(0.22, 0.48, 0.25, 0.95)
        else
            love.graphics.setColor(0.15, 0.22, 0.26, 0.92)
        end
        love.graphics.rectangle("fill", item._x, item._y, item._w, item._h, 8, 8)
        love.graphics.setColor(isHot and 0.65 or 0.42, isHot and 0.98 or 0.68, isHot and 0.55 or 0.48, 1)
        love.graphics.rectangle("line", item._x, item._y, item._w, item._h, 8, 8)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(item.label, item._x + 12, item._y + 8, item._w - 24, "center")
        love.graphics.setColor(0.72, 0.82, 0.78, 1)
        love.graphics.printf(item.sub, item._x + 12, item._y + 26, item._w - 24, "center")
    end

    if self.notice then
        love.graphics.setColor(0.12, 0.14, 0.18, 0.95)
        love.graphics.rectangle("fill", 120, 434, 400, 32, 6, 6)
        love.graphics.setColor(1, 0.85, 0.35, 1)
        love.graphics.printf(self.notice, 120, 443, 400, "center")
    end

    local credHot = (self.hotzones.hoveredId == "credits")
    love.graphics.setColor(credHot and 0.25 or 0.14, credHot and 0.45 or 0.18, credHot and 0.28 or 0.24, 0.92)
    love.graphics.rectangle("fill", 532, 442, 94, 28, 6, 6)
    love.graphics.setColor(0.65, 0.85, 0.68, 1)
    love.graphics.rectangle("line", 532, 442, 94, 28, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Credits", 532, 449, 94, "center")

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
    end
    love.graphics.pop()
end

return Launcher
