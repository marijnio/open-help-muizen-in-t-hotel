-- De Galerij (GALERIJ.EXE): browse all 19 hotel rooms and listen to their music.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local Hotzone = require("src.core.hotzone")
local SceneManager = require("src.core.scene_manager")

local Gallery = {}

-- GALERIJ.EXE Frame 2 channels 3..21 map 1-to-1 to casts 1..19 (alphabetical room order)
local GALLERY_ROOMS = {
    { id = "artist",   title = "Atelier",                   x = 41,  y = 60,  w = 116, h = 85, cast = 1,  snd = "artist" },
    { id = "ballroom", title = "Balzaal",                   x = 461, y = 143, w = 144, h = 85, cast = 2,  snd = "ballroom" },
    { id = "bar",      title = "Bar",                       x = 377, y = 315, w = 116, h = 85, cast = 3,  snd = "bar" },
    { id = "bathroom", title = "Badkamer",                  x = 377, y = 229, w = 116, h = 85, cast = 4,  snd = "bathroom" },
    { id = "business", title = "Zakenkamer",                x = 37,  y = 229, w = 107, h = 85, cast = 5,  snd = "business" },
    { id = "dining",   title = "Eetkamer",                  x = 148, y = 317, w = 116, h = 85, cast = 6,  snd = "dining" },
    { id = "exercise", title = "Fitnessruimte",             x = 493, y = 230, w = 116, h = 85, cast = 7,  snd = "exercise" },
    { id = "farmer",   title = "Boerenkamer",               x = 155, y = 55,  w = 116, h = 85, cast = 8,  snd = "farmer" },
    { id = "kitchen",  title = "Keuken",                    x = 262, y = 316, w = 116, h = 85, cast = 9,  snd = "kitchen" },
    { id = "library",  title = "Leeszaal",                  x = 38,  y = 316, w = 112, h = 85, cast = 10, snd = "library" },
    { id = "madsci",   title = "Laboratorium",              x = 493, y = 56,  w = 114, h = 85, cast = 11, snd = "madsci" },
    { id = "newlywed", title = "Bruidssuite",               x = 39,  y = 143, w = 135, h = 85, cast = 12, snd = "newlywed" },
    { id = "playroom", title = "Speelkamer",                x = 142, y = 229, w = 109, h = 85, cast = 13, snd = "playroom" },
    { id = "plumber",  title = "Loodgieterskamer",          x = 378, y = 58,  w = 114, h = 85, cast = 14, snd = "plumber" },
    { id = "presbed",  title = "Presidentiële Slaapkamer",  x = 177, y = 142, w = 143, h = 85, cast = 15, snd = "presbed" },
    { id = "presliv",  title = "Presidentiële Salon",       x = 319, y = 144, w = 141, h = 85, cast = 16, snd = "presliv" },
    { id = "slobs",    title = "Rommelkamer",               x = 253, y = 230, w = 125, h = 85, cast = 17, snd = "slobs" },
    { id = "snooker",  title = "Biljartzaal",               x = 491, y = 316, w = 116, h = 85, cast = 18, snd = "snooker" },
    { id = "witches",  title = "Heksenkamer",               x = 272, y = 56,  w = 107, h = 85, cast = 19, snd = "witches" },
}

function Gallery:enter()
    Cursor.reset()
    AudioQueue.stopAll()
    self.selectedRoom = nil
    self.hotzones = Hotzone.new()

    for _, r in ipairs(GALLERY_ROOMS) do
        self.hotzones:add({
            id = "gal_" .. r.id,
            room = r,
            x = r.x,
            y = r.y,
            w = r.w,
            h = r.h,
            onClick = function()
                self:openRoom(r)
            end,
        })
    end

    self.hotzones:add({
        id = "gal_exit",
        x = 270,
        y = 442,
        w = 100,
        h = 36,
        onClick = function()
            SceneManager.switch(App.states.launcher)
        end,
    })
end

function Gallery:exit()
    AudioQueue.stopAll()
    Cursor.reset()
end

function Gallery:openRoom(r)
    self.selectedRoom = r
    AudioQueue.playMusic({ group = "startsnd", key = r.snd }, { loop = true, volume = 0.75 })
end

function Gallery:closeRoom()
    self.selectedRoom = nil
    AudioQueue.stopMusic()
end

function Gallery:mousemoved(vx, vy)
    if self.selectedRoom then
        Cursor.setSystem("hand")
        return
    end
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function Gallery:mousepressed(vx, vy, button)
    if button ~= 1 then return end
    if self.selectedRoom then
        self:closeRoom()
    else
        self.hotzones:click(vx, vy)
    end
end

function Gallery:keypressed(key)
    if key == "escape" then
        if self.selectedRoom then
            self:closeRoom()
        else
            SceneManager.switch(App.states.launcher)
        end
        return true
    end
    return false
end

function Gallery:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    if self.selectedRoom then
        local frameIdx = (self.selectedRoom.cast * 2) + 1
        DirectorStage.drawFrame("galerij", frameIdx, { sharedKey = nil })
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 12, 448, 250, 26, 5, 5)
        love.graphics.setColor(1, 0.92, 0.6, 1)
        love.graphics.printf(self.selectedRoom.title, 16, 454, 242, "left")
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 418, 448, 210, 26, 5, 5)
        love.graphics.setColor(0.85, 0.92, 0.95, 1)
        love.graphics.printf("Klik of Esc = Terug", 422, 454, 202, "right")
    else
        love.graphics.setColor(0.95, 0.93, 0.88, 1)
        love.graphics.rectangle("fill", 0, 0, 640, 480)
        DirectorStage.drawFrame("galerij", 2, { sharedKey = nil, hiddenChannels = { [25] = true } })

        local hovered = nil
        for _, r in ipairs(GALLERY_ROOMS) do
            if self.hotzones.hoveredId == ("gal_" .. r.id) then
                hovered = r
                love.graphics.setColor(0.35, 0.95, 0.45, 0.9)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
            end
        end

        love.graphics.setColor(0.10, 0.12, 0.16, 0.88)
        love.graphics.rectangle("fill", 16, 448, 240, 24, 5, 5)
        love.graphics.setColor(1, 0.92, 0.65, 1)
        love.graphics.printf(hovered and hovered.title or "De Galerij • Kies een kamer", 20, 453, 232, "left")

        love.graphics.setColor(0.10, 0.12, 0.16, 0.88)
        love.graphics.rectangle("fill", 390, 448, 234, 24, 5, 5)
        love.graphics.setColor(0.85, 0.9, 0.95, 1)
        love.graphics.printf("Klik op 'Terug' of Esc", 394, 453, 226, "right")
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
    end
    love.graphics.pop()
end

return Gallery
