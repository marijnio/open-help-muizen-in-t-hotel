-- Startup splash sequence showing two skippable intro screens before the launcher menu.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local SceneManager = require("src.core.scene_manager")

local Splash = {}

local SLIDE_DURATION = 3.0

local function loadSecondSlideImage()
    local score = Assets.getDxr("muizen_exe")
    local rel = (score and score.casts and score.casts[9] and score.casts[9].image) or "dxr/muizen_exe/sprites/c_9.png"
    return Assets.getImage(rel)
end

function Splash:enter()
    Cursor.reset()
    AudioQueue.stopAll()
    AudioQueue.playMusic({ group = "root", key = "start" }, { loop = false, volume = 0.65 })

    self.slides = {}
    local first = Assets.getManifestImage("bombilla")
    if first then
        table.insert(self.slides, first)
    end
    local second = loadSecondSlideImage()
    if second then
        table.insert(self.slides, second)
    end

    self.slideIndex = 1
    self.timer = 0

    if #self.slides == 0 then
        SceneManager.switch(App.states.launcher, { keepMusic = true })
    end
end

function Splash:exit()
    Cursor.reset()
end

function Splash:advance()
    self.slideIndex = self.slideIndex + 1
    self.timer = 0
    if self.slideIndex > #self.slides then
        SceneManager.switch(App.states.launcher, { keepMusic = true })
    end
end

function Splash:update(dt)
    self.timer = self.timer + dt
    if self.timer >= SLIDE_DURATION then
        self:advance()
    end
end

function Splash:mousepressed(_vx, _vy, button)
    if button ~= 1 then
        return
    end
    self:advance()
end

function Splash:keypressed(key)
    if key == "escape" or key == "space" or key == "return" or key == "kpenter" or key == "right" then
        self:advance()
        return true
    end
    return false
end

function Splash:draw()
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    local img = self.slides and self.slides[self.slideIndex]
    if img then
        love.graphics.setColor(1, 1, 1, 1)
        local iw, ih = img:getDimensions()
        local s = math.min(640 / iw, 480 / ih)
        local dx = math.floor((640 - iw * s) * 0.5)
        local dy = math.floor((480 - ih * s) * 0.5)
        love.graphics.draw(img, dx, dy, 0, s, s)
    end
    love.graphics.pop()
end

return Splash
