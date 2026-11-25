-- Main entry point for Help! Muizen in 't hotel (LÖVE 12 engine).

local Viewport = require("src.core.viewport")
local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local Save = require("src.core.save")
local SceneManager = require("src.core.scene_manager")
local Rooms = require("src.data.rooms")

local function makeDefaultSession()
    return {
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
        pendingInstrumentRoom = nil,
        buildIndex = 1,
    }
end

App = {
    debugMode = false,
    isTouchMode = false,
    inActiveSession = false,
    focused = true,
    activeTouchId = nil,
    lastVx = 320,
    lastVy = 240,
    session = makeDefaultSession(),
    states = {},
}

local function clampVirtual(vx, vy)
    return math.max(0, math.min(Viewport.VIRTUAL_W, vx)), math.max(0, math.min(Viewport.VIRTUAL_H, vy))
end

function App.saveProgress()
    if not App.inActiveSession or not App.session then
        return false
    end
    local caught = App.session.caughtCount or 0
    if caught >= Rooms.TOTAL_MICE and not App.session.pendingInstrumentRoom then
        return false
    end
    return Save.write(App.session)
end

function App.clearAllProgress()
    Save.clearAll()
    App.inActiveSession = false
    App.session = makeDefaultSession()
    App.superSession = nil
end

function App.reloadAssets()
    return Assets.init()
end

function App.enterInitialScene()
    SceneManager.switch(App.states.splash)
end

function love.load()
    Viewport.init()
    Cursor.init()

    local font = love.graphics.newFont(14)
    love.graphics.setFont(font)

    App.states = {
        missing_assets = require("src.states.missing_assets"),
        splash = require("src.states.splash"),
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
        doolhof = require("src.states.doolhof"),
        super_hub = require("src.states.super_hub"),
        super_room = require("src.states.super_room"),
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
    if focused == App.focused then
        return
    end
    App.focused = focused
    if not focused then
        App.activeTouchId = nil
        App.saveProgress()
        AudioQueue.pauseAll()
    else
        AudioQueue.resumeAll()
    end
    if SceneManager.current and SceneManager.current.onFocus then
        SceneManager.current:onFocus(focused)
    end
    if SceneManager.overlay and SceneManager.overlay.onFocus then
        SceneManager.overlay:onFocus(focused)
    end
end

function love.quit()
    App.saveProgress()
end

function love.update(dt)
    if not App.focused then
        return
    end
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
    local vx, vy = clampVirtual(Viewport.screenToVirtual(sx, sy))
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousemoved(vx, vy)
end

function love.mousepressed(sx, sy, button, istouch)
    if istouch then return end
    App.isTouchMode = false
    local vx, vy, inside = Viewport.screenToVirtual(sx, sy)
    if not inside then return end
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousepressed(vx, vy, button)
end

function love.mousereleased(sx, sy, button, istouch)
    if istouch then return end
    App.isTouchMode = false
    local vx, vy = clampVirtual(Viewport.screenToVirtual(sx, sy))
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousereleased(vx, vy, button)
end

function love.touchpressed(id, sx, sy)
    App.isTouchMode = true
    if App.activeTouchId ~= nil then return end
    local vx, vy, inside = Viewport.screenToVirtual(sx, sy)
    if not inside then return end
    App.activeTouchId = id
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousemoved(vx, vy)
    SceneManager.mousepressed(vx, vy, 1)
end

function love.touchmoved(id, sx, sy)
    if App.activeTouchId ~= id then return end
    App.isTouchMode = true
    local vx, vy = clampVirtual(Viewport.screenToVirtual(sx, sy))
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousemoved(vx, vy)
end

function love.touchreleased(id, sx, sy)
    if App.activeTouchId ~= id then return end
    App.activeTouchId = nil
    App.isTouchMode = true
    local vx, vy = clampVirtual(Viewport.screenToVirtual(sx, sy))
    App.lastVx, App.lastVy = vx, vy
    SceneManager.mousereleased(vx, vy, 1)
end

function love.keypressed(key)
    if key == "acback" then
        key = "escape"
    end
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
