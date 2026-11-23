-- Intro video state (DUTVIDEO/ENGINTRO.MOV) with skip-to-start-menu.

local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local SceneManager = require("src.core.scene_manager")
local VideoPlayer = require("src.core.video_player")

local Intro = {}

function Intro:enter(params)
    Cursor.reset()
    AudioQueue.stopAll()
    self.returnState = (params and params.returnState) or App.states.start_menu
    self.returnParams = params and params.returnParams
    self.player = VideoPlayer.new("engintro", {
        onFinish = function()
            SceneManager.switch(self.returnState, self.returnParams)
        end,
    })
    if not self.player then
        SceneManager.switch(self.returnState, self.returnParams)
    end
end

function Intro:exit()
    if self.player then
        self.player:stop()
        self.player = nil
    end
end

function Intro:onFocus(focused)
    if not self.player then return end
    if focused then
        self.player:resume()
    else
        self.player:pause()
    end
end

function Intro:update(dt)
    if self.player then
        self.player:update(dt)
    end
end

function Intro:mousepressed(_vx, _vy, button)
    if button ~= 1 then return end
    SceneManager.switch(self.returnState, self.returnParams)
end

function Intro:keypressed(key)
    if key == "escape" or key == "space" or key == "return" then
        SceneManager.switch(self.returnState, self.returnParams)
        return true
    end
    return false
end

function Intro:draw()
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)
    if self.player then
        self.player:draw()
    end
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 454, 450, 180, 24, 5, 5)
    love.graphics.setColor(0.92, 0.94, 0.96, 0.9)
    love.graphics.printf("Klik / Esc = Overslaan", 454, 455, 180, "center")
    love.graphics.pop()
end

return Intro
