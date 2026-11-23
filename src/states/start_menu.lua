-- Main game Options / Start Menu (GGMDMENU Frame 7).

local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local Hotzone = require("src.core.hotzone")
local Save = require("src.core.save")
local SceneManager = require("src.core.scene_manager")
local Rooms = require("src.data.rooms")

local StartMenu = {}

local DIFFICULTY_CASTS = { [1] = 11, [2] = 12, [3] = 13 }
local MUSIC_CASTS = { [true] = 15, [false] = 14 }

function StartMenu:enter()
    Cursor.reset()
    AudioQueue.stopAll()
    self.frameNum = DirectorStage.getLabelFrame("ggmdmenu", "start") or 7
    self.difficulty = App.session.difficulty or 1
    self.musicEnabled = (App.session.musicEnabled ~= false)
    self.notice = nil
    self.noticeTimer = 0

    AudioQueue.setMusicEnabled(self.musicEnabled)
    if self.musicEnabled then
        AudioQueue.playMusic({ group = "root", key = "start" }, { loop = true, volume = 0.55 })
    end

    self.hotzones = Hotzone.new()
    -- GGMDMENU Frame 7 exact hotzones
    self.hotzones:add({ id = "level_1", x = 240, y = 58,  w = 177, h = 41, onClick = function() self:setDifficulty(1) end })
    self.hotzones:add({ id = "level_2", x = 238, y = 101, w = 180, h = 41, onClick = function() self:setDifficulty(2) end })
    self.hotzones:add({ id = "level_3", x = 242, y = 144, w = 171, h = 43, onClick = function() self:setDifficulty(3) end })

    self.hotzones:add({ id = "music_on",  x = 245, y = 240, w = 162, h = 40, onClick = function() self:setMusic(true) end })
    self.hotzones:add({ id = "music_off", x = 242, y = 282, w = 168, h = 39, onClick = function() self:setMusic(false) end })

    self.hotzones:add({ id = "start_new", x = 193, y = 359, w = 138, h = 52, onClick = function() self:startNewGame() end })
    self.hotzones:add({ id = "load_game", x = 338, y = 359, w = 138, h = 52, onClick = function() self:loadSavedGame() end })

    self.hotzones:add({ id = "back_launcher", x = 18, y = 440, w = 54, h = 39, onClick = function()
        SceneManager.switch(App.states.launcher)
    end })
    self.hotzones:add({ id = "watch_intro", x = 510, y = 446, w = 120, h = 28, onClick = function()
        SceneManager.switch(App.states.intro, { returnState = App.states.start_menu })
    end })
end

function StartMenu:exit()
    AudioQueue.stopMusic()
    Cursor.reset()
end

function StartMenu:setDifficulty(lvl)
    self.difficulty = lvl
    App.session.difficulty = lvl
    AudioQueue.playSfx("dxr/shared/sounds/s_822.wav", 0.5)
end

function StartMenu:setMusic(enabled)
    self.musicEnabled = enabled
    App.session.musicEnabled = enabled
    AudioQueue.setMusicEnabled(enabled)
    if enabled then
        AudioQueue.playMusic({ group = "root", key = "start" }, { loop = true, volume = 0.55 })
    end
end

function StartMenu:startNewGame()
    local trapsByDiff = { [1] = 10, [2] = 5, [3] = 0 }
    local mouseRooms = {}
    -- 19 mice for the 19 orchestra instruments across the 20 rooms (always include attic + 18 of 19 standard rooms)
    local standardIds = {}
    for _, r in ipairs(Rooms.LIST) do
        if r.id ~= "attic" then
            table.insert(standardIds, r.id)
        end
    end
    local skipIdx = love.math.random(1, #standardIds)
    for i, id in ipairs(standardIds) do
        mouseRooms[id] = (i ~= skipIdx)
    end
    mouseRooms["attic"] = true

    App.session = {
        difficulty = self.difficulty,
        musicEnabled = self.musicEnabled,
        trapsLeft = trapsByDiff[self.difficulty] or 10,
        caughtMice = {},
        caughtCount = 0,
        mouseRooms = mouseRooms,
        seenIntros = {},
        foundInstruments = {},
        lastInstrument = nil,
        buildIndex = love.math.random(1, 3),
    }
    SceneManager.switch(App.states.hotel_hub)
end

function StartMenu:loadSavedGame()
    local saved = Save.load()
    if not saved then
        self.notice = "Geen opgeslagen spel gevonden!"
        self.noticeTimer = 2.5
        return
    end
    App.session = saved
    AudioQueue.setMusicEnabled(App.session.musicEnabled ~= false)
    SceneManager.switch(App.states.hotel_hub)
end

function StartMenu:update(dt)
    if self.noticeTimer > 0 then
        self.noticeTimer = self.noticeTimer - dt
        if self.noticeTimer <= 0 then
            self.notice = nil
        end
    end
end

function StartMenu:mousemoved(vx, vy)
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function StartMenu:mousepressed(vx, vy, button)
    if button == 1 then
        self.hotzones:click(vx, vy)
    end
end

function StartMenu:keypressed(key)
    if key == "escape" then
        SceneManager.switch(App.states.launcher)
        return true
    elseif key == "1" or key == "2" or key == "3" then
        self:setDifficulty(tonumber(key))
        return true
    elseif key == "return" then
        self:startNewGame()
        return true
    end
    return false
end

function StartMenu:draw(vx, vy)
    love.graphics.push("all")
    DirectorStage.drawFrame("ggmdmenu", self.frameNum, {
        channelCasts = {
            [4] = DIFFICULTY_CASTS[self.difficulty] or 11,
            [5] = MUSIC_CASTS[self.musicEnabled],
        },
    })

    -- Subtle modern helper pills at bottom corners
    love.graphics.setColor(0.10, 0.12, 0.16, 0.85)
    love.graphics.rectangle("fill", 510, 446, 120, 28, 6, 6)
    love.graphics.setColor(0.85, 0.90, 0.72, 1)
    love.graphics.rectangle("line", 510, 446, 120, 28, 6, 6)
    love.graphics.printf("Intro bekijken", 510, 453, 120, "center")

    if self.notice then
        love.graphics.setColor(0.1, 0.1, 0.14, 0.92)
        love.graphics.rectangle("fill", 180, 422, 280, 30, 6, 6)
        love.graphics.setColor(1, 0.85, 0.35, 1)
        love.graphics.printf(self.notice, 180, 430, 280, "center")
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
    end
    love.graphics.pop()
end

return StartMenu
