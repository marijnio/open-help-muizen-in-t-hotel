-- Main entry point for Help! Muizen in 't hotel (LÖVE 12 engine).

local Viewport = require("src.core.viewport")
local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local SceneManager = require("src.core.scene_manager")

App = {
    debugMode = false,
    isTouchMode = false,
    lastVx = 320,
    lastVy = 240,
    session = {
        difficulty = 1,
        musicEnabled = true,
        trapsLeft = 10,
        caughtMice = {},
        caughtCount = 0,
        roomQueue = {},
        activeMouseRoom = nil,
        mouseRooms = {},
        seenIntros = {},
        foundInstruments = {},
        lastInstrument = nil,
        buildIndex = 1,
    },
    states = {},
}

function App.reloadAssets()
    return Assets.init()
end

function App.enterInitialScene()
    SceneManager.switch(App.states.launcher)
end

function love.load()
    Viewport.init()
    Cursor.init()

    local font = love.graphics.newFont(14)
    love.graphics.setFont(font)

    App.states = {
        missing_assets = require("src.states.missing_assets"),
        launcher = require("src.states.launcher"),
        intro = require("src.states.intro"),
        start_menu = require("src.states.start_menu"),
        hotel_hub = require("src.states.hotel_hub"),
        room = require("src.states.room"),
        attic = require("src.states.attic"),
        instrum = require("src.states.instrum"),
        orch = require("src.states.orch"),
        finale = require("src.states.finale"),
        credits = require("src.states.credits"),
    }

    if App.reloadAssets() then
        App.enterInitialScene()
    else
        SceneManager.switch(App.states.missing_assets)
    end
end

function love.resize()
    Viewport.recalculate()
end

function love.focus(focused)
    if focused then
        AudioQueue.resumeAll()
    else
        AudioQueue.pauseAll()
    end
    if SceneManager.current and SceneManager.current.onFocus then
        SceneManager.current:onFocus(focused)
    end
    if SceneManager.overlay and SceneManager.overlay.onFocus then
        SceneManager.overlay:onFocus(focused)
    end
end

function love.update(dt)
    dt = math.min(dt, 0.1)
    AudioQueue.update(dt)
    SceneManager.update(dt)
end

function love.draw()
    Viewport.beginDraw()
    SceneManager.draw(App.lastVx, App.lastVy)
    Viewport.endDraw()
end

function love.mousemoved(sx, sy, _dx, _dy, istouch)
    if istouch then return end
    App.isTouchMode = false
    local vx, vy = Viewport.screenToVirtual(sx, sy)
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousemoved(vx, vy)
end

function love.mousepressed(sx, sy, button, istouch)
    if istouch then return end
    App.isTouchMode = false
    local vx, vy = Viewport.screenToVirtual(sx, sy)
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousepressed(vx, vy, button)
end

function love.mousereleased(sx, sy, button, istouch)
    if istouch then return end
    App.isTouchMode = false
    local vx, vy = Viewport.screenToVirtual(sx, sy)
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousereleased(vx, vy, button)
end

function love.touchpressed(_id, sx, sy)
    App.isTouchMode = true
    local vx, vy = Viewport.screenToVirtual(sx, sy)
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousemoved(vx, vy)
    SceneManager.mousepressed(vx, vy, 1)
end

function love.touchmoved(_id, sx, sy)
    App.isTouchMode = true
    local vx, vy = Viewport.screenToVirtual(sx, sy)
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousemoved(vx, vy)
end

function love.touchreleased(_id, sx, sy)
    App.isTouchMode = true
    local vx, vy = Viewport.screenToVirtual(sx, sy)
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousereleased(vx, vy, 1)
end

function love.keypressed(key)
    if key == "f1" then
        App.debugMode = not App.debugMode
        return
    elseif key == "f2" then
        Viewport.toggleFilter()
        return
    elseif key == "f11" then
        love.window.setFullscreen(not love.window.getFullscreen())
        Viewport.recalculate()
        return
    end
    SceneManager.keypressed(key)
end
