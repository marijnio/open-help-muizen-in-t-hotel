-- Credits sequence (CREDITS.DXR) accompanied by the full 19-instrument orchestra track.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local SceneManager = require("src.core.scene_manager")

local Credits = {}

function Credits:enter()
    Cursor.reset()
    AudioQueue.stopAll()
    self.score = Assets.getDxr("credits")
    self.fps = (self.score and self.score.fps) or 11
    local totalFrames = (self.score and self.score.frames and #self.score.frames) or 355

    self.validFrames = {}
    if self.score and self.score.frames then
        for i = 7, totalFrames do
            local fr = self.score.frames[i]
            if fr and #fr > 0 then
                table.insert(self.validFrames, i)
            end
        end
    end
    if #self.validFrames == 0 then
        table.insert(self.validFrames, 7)
    end
    self.frameIdxFloat = 1

    if App.session.musicEnabled ~= false then
        AudioQueue.playMusic({ group = "music_build1", key = "vibes" }, { loop = true, volume = 0.75 })
    end
end

function Credits:exit()
    AudioQueue.stopAll()
    Cursor.reset()
end

function Credits:update(dt)
    self.frameIdxFloat = self.frameIdxFloat + dt * self.fps
    if self.frameIdxFloat > #self.validFrames + 0.99 then
        SceneManager.switch(App.states.launcher)
    end
end

function Credits:mousepressed()
    SceneManager.switch(App.states.launcher)
end

function Credits:keypressed(key)
    if key == "escape" or key == "space" or key == "return" then
        SceneManager.switch(App.states.launcher)
        return true
    end
    return false
end

function Credits:draw()
    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    local idx = math.max(1, math.min(#self.validFrames, math.floor(self.frameIdxFloat)))
    local frameNum = self.validFrames[idx]
    DirectorStage.drawFrame("credits", frameNum, { sharedKey = nil })

    love.graphics.setColor(0.08, 0.10, 0.14, 0.85)
    love.graphics.rectangle("fill", 390, 448, 240, 24, 5, 5)
    love.graphics.setColor(0.95, 0.95, 0.95, 0.95)
    love.graphics.printf("Klik / Esc = Terug naar start", 394, 453, 232, "center")
    love.graphics.pop()
end

return Credits
