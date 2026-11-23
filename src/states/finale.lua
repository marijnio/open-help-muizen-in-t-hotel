-- Grand Finale cutscene (ENDSEQ.MOV) played when all 19 mice are reunited.

local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local Save = require("src.core.save")
local SceneManager = require("src.core.scene_manager")
local VideoPlayer = require("src.core.video_player")

local Finale = {}

function Finale:enter()
    Cursor.reset()
    AudioQueue.stopAll()
    App.inActiveSession = false
    Save.delete()
    self.player = VideoPlayer.new("endseq", {
        onFinish = function()
            SceneManager.switch(App.states.credits)
        end,
    })
    if not self.player then
        SceneManager.switch(App.states.credits)
    end
end

function Finale:exit()
    if self.player then
        self.player:stop()
        self.player = nil
    end
end

function Finale:onFocus(focused)
    if not self.player then return end
    if focused then self.player:resume() else self.player:pause() end
end

function Finale:update(dt)
    if self.player then
        self.player:update(dt)
    end
end

function Finale:mousepressed(_vx, _vy, button)
    if button ~= 1 then return end
    SceneManager.switch(App.states.credits)
end

function Finale:keypressed(key)
    if key == "escape" or key == "space" or key == "return" then
        SceneManager.switch(App.states.credits)
        return true
    end
    return false
end

function Finale:draw()
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)
    if self.player then
        self.player:draw()
    end
    love.graphics.setColor(0.08, 0.12, 0.10, 0.85)
    love.graphics.rectangle("fill", 70, 6, 500, 26, 6, 6)
    love.graphics.setColor(0.55, 1.0, 0.50, 1)
    love.graphics.printf("Gefeliciteerd! Het Grote Groene Muizenorkest is compleet!", 76, 12, 488, "center")

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 434, 448, 198, 24, 5, 5)
    love.graphics.setColor(0.95, 0.95, 0.95, 0.9)
    love.graphics.printf("Klik / Esc = Naar Credits", 438, 453, 190, "center")
    love.graphics.pop()
end

return Finale
