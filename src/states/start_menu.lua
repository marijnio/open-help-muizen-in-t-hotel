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

function StartMenu:enter(params)
    Cursor.reset()
    AudioQueue.stopAll()
    self.frameNum = DirectorStage.getLabelFrame("ggmdmenu", "start") or 7
    self.resumeFrameNum = 6
    self.difficulty = App.session.difficulty or 1
    self.musicEnabled = (App.session.musicEnabled ~= false)
    self.notice = nil
    self.noticeTimer = 0
    self.saveSummary = Save.peekSummary()
    self.hasSave = (self.saveSummary ~= nil)

    AudioQueue.setMusicEnabled(self.musicEnabled)
    if self.musicEnabled then
        AudioQueue.playMusic({ group = "root", key = "start" }, { loop = true, volume = 0.55 })
    end

    if self.hasSave and not (params and params.skipResumePrompt) then
        self:showResumePrompt()
    else
        self:showOptions()
    end
end

function StartMenu:showResumePrompt()
    self.mode = "resume_prompt"
    self.hotzones = Hotzone.new()
    -- GGMDMENU Frame 6 exact hotzones ("Wil je verder gaan met een bestaand spel?")
    self.hotzones:add({ id = "resume_no",  x = 221, y = 264, w = 79, h = 47, onClick = function() self:showOptions() end })
    self.hotzones:add({ id = "resume_yes", x = 313, y = 262, w = 88, h = 45, onClick = function() self:loadSavedGame() end })
    self.hotzones:add({ id = "back_launcher", x = 18, y = 440, w = 54, h = 39, onClick = function()
        SceneManager.switch(App.states.launcher)
    end })
    Cursor.reset()
end

function StartMenu:showOptions()
    self.mode = "options"
    self.hotzones = Hotzone.new()
    -- GGMDMENU Frame 7 exact hotzones
    self.hotzones:add({ id = "level_1", x = 240, y = 58,  w = 177, h = 41, onClick = function() self:setDifficulty(1) end })
    self.hotzones:add({ id = "level_2", x = 238, y = 101, w = 180, h = 41, onClick = function() self:setDifficulty(2) end })
    self.hotzones:add({ id = "level_3", x = 242, y = 144, w = 171, h = 43, onClick = function() self:setDifficulty(3) end })

    self.hotzones:add({ id = "music_on",  x = 245, y = 240, w = 162, h = 40, onClick = function() self:setMusic(true) end })
    self.hotzones:add({ id = "music_off", x = 242, y = 282, w = 168, h = 39, onClick = function() self:setMusic(false) end })

    self.hotzones:add({ id = "quit_menu", x = 193, y = 359, w = 138, h = 52, onClick = function()
        SceneManager.switch(App.states.launcher)
    end })
    self.hotzones:add({ id = "start_new", x = 338, y = 359, w = 138, h = 52, onClick = function() self:startNewGame() end })

    self.hotzones:add({ id = "back_launcher", x = 18, y = 440, w = 54, h = 39, onClick = function()
        SceneManager.switch(App.states.launcher)
    end })
    self.hotzones:add({ id = "watch_intro", x = 510, y = 446, w = 120, h = 28, onClick = function()
        SceneManager.switch(App.states.intro, {
            returnState = App.states.start_menu,
            returnParams = { skipResumePrompt = true },
        })
    end })
    if self.hasSave then
        self.hotzones:add({ id = "load_game", x = 80, y = 446, w = 148, h = 28, onClick = function() self:loadSavedGame() end })
    end
    Cursor.reset()
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

    App.session = {
        difficulty = self.difficulty,
        musicEnabled = self.musicEnabled,
        trapsLeft = trapsByDiff[self.difficulty] or 10,
        caughtMice = {},
        caughtCount = 0,
        roomQueue = {},
        activeMouseRoom = nil,
        mouseRooms = {},
        seenIntros = {},
        foundInstruments = {},
        lastInstrument = nil,
        pendingInstrumentRoom = nil,
        buildIndex = love.math.random(1, 3),
    }
    Rooms.initSessionRooms(App.session)
    App.inActiveSession = true
    SceneManager.switch(App.states.hotel_hub)
end

function StartMenu:loadSavedGame()
    local saved = Save.load()
    if not saved then
        self.saveSummary = Save.peekSummary()
        self.hasSave = (self.saveSummary ~= nil)
        if self.mode ~= "options" then
            self:showOptions()
        end
        self.notice = "Geen opgeslagen spel gevonden!"
        self.noticeTimer = 2.5
        return
    end
    App.session = saved
    Rooms.normalizeSession(App.session)
    App.inActiveSession = true
    AudioQueue.setMusicEnabled(App.session.musicEnabled ~= false)
    if App.session.pendingInstrumentRoom then
        SceneManager.switch(App.states.instrum, { roomTitle = App.session.pendingInstrumentRoom })
    elseif (App.session.caughtCount or 0) >= Rooms.TOTAL_MICE then
        SceneManager.switch(App.states.finale)
    else
        SceneManager.switch(App.states.hotel_hub)
    end
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
    if self.mode == "resume_prompt" then
        if key == "escape" then
            SceneManager.switch(App.states.launcher)
            return true
        elseif key == "return" or key == "j" or key == "y" then
            self:loadSavedGame()
            return true
        elseif key == "n" then
            self:showOptions()
            return true
        end
        return false
    end

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

local function drawPill(x, y, w, h, label, hovered)
    love.graphics.setColor(hovered and 0.18 or 0.10, hovered and 0.24 or 0.12, hovered and 0.20 or 0.16, 0.90)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)
    love.graphics.setColor(0.85, 0.90, 0.72, 1)
    love.graphics.rectangle("line", x, y, w, h, 6, 6)
    love.graphics.printf(label, x, y + 7, w, "center")
end

function StartMenu:draw(vx, vy)
    love.graphics.push("all")
    if self.mode == "resume_prompt" then
        DirectorStage.drawFrame("ggmdmenu", self.resumeFrameNum)
        if self.saveSummary then
            love.graphics.setColor(0.08, 0.10, 0.14, 0.90)
            love.graphics.rectangle("fill", 120, 446, 400, 26, 6, 6)
            love.graphics.setColor(0.65, 0.85, 0.68, 1)
            love.graphics.rectangle("line", 120, 446, 400, 26, 6, 6)
            love.graphics.setColor(0.95, 0.92, 0.68, 1)
            love.graphics.printf(
                string.format(
                    "Opgeslagen spel: %d/19 muizen  •  Niveau %d  •  Vallen: %d",
                    self.saveSummary.caughtCount,
                    self.saveSummary.difficulty,
                    self.saveSummary.trapsLeft
                ),
                124,
                452,
                392,
                "center"
            )
        end
    else
        DirectorStage.drawFrame("ggmdmenu", self.frameNum, {
            channelCasts = {
                [4] = DIFFICULTY_CASTS[self.difficulty] or 11,
                [5] = MUSIC_CASTS[self.musicEnabled],
            },
        })

        -- Subtle modern helper pills at bottom corners
        drawPill(510, 446, 120, 28, "Intro bekijken", self.hotzones.hoveredId == "watch_intro")
        if self.hasSave and self.saveSummary then
            drawPill(
                80,
                446,
                148,
                28,
                string.format("Verder (%d/19)", self.saveSummary.caughtCount),
                self.hotzones.hoveredId == "load_game"
            )
        end
    end

    if self.notice then
        love.graphics.setColor(0.1, 0.1, 0.14, 0.92)
        love.graphics.rectangle("fill", 180, 414, 280, 26, 6, 6)
        love.graphics.setColor(1, 0.85, 0.35, 1)
        love.graphics.printf(self.notice, 180, 420, 280, "center")
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
    end
    love.graphics.pop()
end

return StartMenu
