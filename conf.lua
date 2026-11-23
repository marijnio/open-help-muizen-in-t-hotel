-- LÖVE configuration targeting LÖVE 12.0 (with 11.5 compatibility guard)

function love.conf(t)
    t.identity = "help-muizen-hotel"
    t.appendidentity = false
    t.console = false
    t.externalstorage = true

    local major = 12
    if love.getVersion then
        major = select(1, love.getVersion())
    end

    local isMobile = false
    if love.system and love.system.getOS then
        local osName = love.system.getOS()
        isMobile = (osName == "Android" or osName == "iOS")
    end

    t.window.title = "Help! Muizen in 't hotel"
    t.window.width = 1280
    t.window.height = 960
    t.window.minwidth = 640
    t.window.minheight = 480
    t.window.resizable = true
    t.window.fullscreen = isMobile
    t.window.vsync = 1

    if major >= 12 then
        t.highdpi = true
    else
        t.window.highdpi = true
    end

    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.sound = true
    t.modules.system = true
    t.modules.timer = true
    t.modules.touch = true
    t.modules.video = false
    t.modules.window = true
    t.modules.physics = false
    t.modules.joystick = false
    t.modules.thread = false
end
