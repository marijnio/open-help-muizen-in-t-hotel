-- Hotel Cross-Section Hub (GGMDMENU Frame 14) with Mouse-Detector TV scanner,
-- Fat Lazy Cat hint video (CATHELP6), Save & Exit dialog, and Milestone 1 room preview.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local ConfirmDialog = require("src.core.confirm_dialog")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local Hotzone = require("src.core.hotzone")
local Save = require("src.core.save")
local SceneManager = require("src.core.scene_manager")
local VideoPlayer = require("src.core.video_player")
local Rooms = require("src.data.rooms")

local HotelHub = {}

-- Modal overlay for Fat Lazy Cat hint video (320x200) or Room intro preview (640x480)
local MediaPreviewOverlay = {}

function MediaPreviewOverlay:enter(params)
    Cursor.reset()
    AudioQueue.stopAll()
    self.title = params.title or ""
    self.roomDxr = params.roomDxr
    self.isHint = params.isHint
    self.showingRoomBg = false
    self.player = params.videoKey and VideoPlayer.new(params.videoKey, {
        onFinish = function()
            if self.roomDxr then
                self.showingRoomBg = true
            else
                SceneManager.clearOverlay()
            end
        end,
    }) or nil
    if not self.player then
        if self.roomDxr then
            self.showingRoomBg = true
        else
            SceneManager.clearOverlay()
        end
    end
end

function MediaPreviewOverlay:exit()
    if self.player then
        self.player:stop()
        self.player = nil
    end
end

function MediaPreviewOverlay:update(dt)
    if self.player and not self.showingRoomBg then
        self.player:update(dt)
    end
end

function MediaPreviewOverlay:mousepressed()
    if self.player and not self.showingRoomBg then
        self.player:stop()
        if self.roomDxr then
            self.showingRoomBg = true
        else
            SceneManager.clearOverlay()
        end
    else
        SceneManager.clearOverlay()
    end
end

function MediaPreviewOverlay:keypressed(key)
    if key == "escape" or key == "space" or key == "return" then
        self:mousepressed()
        return true
    end
    return true
end

function MediaPreviewOverlay:draw()
    love.graphics.push("all")
    if self.isHint then
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", 0, 0, 640, 480)
        if self.player then
            self.player:draw()
        end
        love.graphics.setColor(1, 0.92, 0.6, 1)
        love.graphics.printf("De Dikke Luie Kater • Klik of Esc om te sluiten", 120, 355, 400, "center")
    elseif self.showingRoomBg and self.roomDxr then
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", 0, 0, 640, 480)
        local f = DirectorStage.getLabelFrame(self.roomDxr, "loop1") or 22
        DirectorStage.drawFrame(self.roomDxr, f)
        love.graphics.setColor(0.08, 0.1, 0.14, 0.88)
        love.graphics.rectangle("fill", 70, 434, 500, 36, 8, 8)
        love.graphics.setColor(0.95, 0.85, 0.4, 1)
        love.graphics.printf(self.title .. " (Kamer-gameplay komt in Milestone 2 • Klik/Esc = Terug)", 76, 445, 488, "center")
    else
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", 0, 0, 640, 480)
        if self.player then
            self.player:draw()
        end
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 454, 450, 180, 24, 5, 5)
        love.graphics.setColor(0.95, 0.95, 0.95, 0.9)
        love.graphics.printf("Klik / Esc = Overslaan", 454, 455, 180, "center")
    end
    love.graphics.pop()
end

function HotelHub:enter(params)
    self.frameNum = DirectorStage.getLabelFrame("ggmdmenu", "select") or 14
    self.hotzones = Hotzone.new()
    self.detectedRoom = nil
    self.touchSelectedRoomId = nil
    self.scannerVisible = false
    self.lastScanSfxAt = -10
    self.banner = nil
    self.bannerTimer = 0
    if params and params.justCaught then
        local caught = (App.session and App.session.caughtCount) or 0
        if caught >= 19 then
            self.banner = "Alle 19 muizen zijn herenigd in het orkest!"
        else
            self.banner = string.format("Muis gevangen in %s! (%d/19)", params.justCaught, caught)
        end
        self.bannerTimer = 3.5
    end

    for _, room in ipairs(Rooms.LIST) do
        self.hotzones:add({
            id = "room_" .. room.id,
            room = room,
            x = room.x,
            y = room.y,
            w = room.w,
            h = room.h,
            onHover = function()
                self:onRoomHover(room)
            end,
            onLeave = function()
                if self.detectedRoom and self.detectedRoom.id == room.id then
                    self.detectedRoom = nil
                end
            end,
            onClick = function()
                self:onRoomClick(room)
            end,
        })
    end

    -- Bottom-left hotel icon (Exit / Save) & bottom-right Fat Lazy Cat basket (Help)
    self.hotzones:add({
        id = "exit_hotel",
        x = 18,
        y = 438,
        w = 56,
        h = 40,
        onClick = function()
            self:promptExit()
        end,
    })
    self.hotzones:add({
        id = "cat_help",
        x = 570,
        y = 438,
        w = 60,
        h = 40,
        onClick = function()
            SceneManager.setOverlay(MediaPreviewOverlay, {
                title = "Dikke Luie Kater",
                videoKey = "cathelp6",
                isHint = true,
            })
        end,
    })

    if (App.session and App.session.caughtCount or 0) > 0 then
        self.hotzones:add({
            id = "open_orch",
            x = 466,
            y = 449,
            w = 84,
            h = 24,
            onClick = function()
                SceneManager.switch(App.states.orch, { previewOnly = true })
            end,
        })
    end
end

function HotelHub:exit()
    AudioQueue.stopVo()
    Cursor.reset()
end

function HotelHub:roomHasMouse(roomId)
    local mr = App.session and App.session.mouseRooms
    return mr and mr[roomId] == true
end

function HotelHub:onRoomHover(room)
    if self:roomHasMouse(room.id) then
        self.detectedRoom = room
        local now = love.timer.getTime()
        if not App.isTouchMode and (now - self.lastScanSfxAt) > 0.65 then
            self.lastScanSfxAt = now
            AudioQueue.playSfx("dxr/ggmdmenu/sounds/s_27.wav", 0.55)
            if room.startsnd and (App.session.musicEnabled ~= false) then
                AudioQueue.clearAndPlay({ group = "startsnd", key = room.startsnd })
            end
        end
    else
        self.detectedRoom = nil
    end
end

function HotelHub:onRoomClick(room)
    if App.isTouchMode and self.touchSelectedRoomId ~= room.id then
        self.touchSelectedRoomId = room.id
        if self:roomHasMouse(room.id) then
            self.detectedRoom = room
            AudioQueue.playSfx("dxr/ggmdmenu/sounds/s_27.wav", 0.55)
            if room.startsnd and (App.session.musicEnabled ~= false) then
                AudioQueue.clearAndPlay({ group = "startsnd", key = room.startsnd })
            end
        else
            self.detectedRoom = nil
        end
        return
    end

    if room.id == "attic" then
        SceneManager.switch(App.states.attic)
    else
        SceneManager.switch(App.states.room, { room = room })
    end
end

function HotelHub:update(dt)
    if self.bannerTimer > 0 then
        self.bannerTimer = self.bannerTimer - dt
        if self.bannerTimer <= 0 then
            self.banner = nil
        end
    end
end

function HotelHub:promptExit()
    Cursor.reset()
    SceneManager.setOverlay(ConfirmDialog, {
        title = "Terug naar hoofdmenu",
        message = "Wil je het huidige spel opslaan voordat je stopt?",
        buttons = {
            {
                label = "Opslaan",
                key = "return",
                action = function()
                    Save.write(App.session)
                    SceneManager.clearOverlay()
                    SceneManager.switch(App.states.start_menu)
                end,
            },
            {
                label = "Niet opslaan",
                action = function()
                    SceneManager.clearOverlay()
                    SceneManager.switch(App.states.start_menu)
                end,
            },
            {
                label = "Annuleren",
                key = "escape",
                action = function()
                    SceneManager.clearOverlay()
                end,
            },
        },
    })
end

function HotelHub:mousemoved(vx, vy)
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    local inHotelArea = (not App.isTouchMode) and vy < 435
    self.scannerVisible = inHotelArea
    if inHotelArea then
        Cursor.setVisible(false)
    else
        Cursor.setVisible(true)
        Cursor.setSystem(hit and "hand" or "arrow")
    end
end

function HotelHub:mousepressed(vx, vy, button)
    if button == 1 then
        self.hotzones:click(vx, vy)
    end
end

function HotelHub:keypressed(key)
    if key == "escape" then
        self:promptExit()
        return true
    end
    return false
end

function HotelHub:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0.95, 0.93, 0.88, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    DirectorStage.drawFrame("ggmdmenu", self.frameNum, {
        hiddenChannels = { [25] = true },
    })

    -- Subtle badge on rooms where a mouse has already been caught
    local caughtMap = (App.session and App.session.caughtMice) or {}
    for _, r in ipairs(Rooms.LIST) do
        if caughtMap[r.id] then
            love.graphics.setColor(0.12, 0.55, 0.22, 0.78)
            love.graphics.circle("fill", r.x + r.w - 12, r.y + 12, 9)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("✓", r.x + r.w - 17, r.y + 4)
        end
    end

    if self.banner then
        love.graphics.setColor(0.08, 0.28, 0.14, 0.94)
        love.graphics.rectangle("fill", 90, 412, 460, 28, 6, 6)
        love.graphics.setColor(0.55, 1.0, 0.55, 1)
        love.graphics.rectangle("line", 90, 412, 460, 28, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(self.banner, 94, 419, 452, "center")
    end

    -- Highlight hovered/selected room subtly + draw bottom bar status
    local caught = (App.session and App.session.caughtCount) or 0
    local traps = (App.session and App.session.trapsLeft) or 0
    local pillW = (caught > 0) and 362 or 448
    love.graphics.setColor(0.12, 0.14, 0.18, 0.9)
    love.graphics.rectangle("fill", 96, 449, pillW, 24, 5, 5)
    love.graphics.setColor(0.95, 0.92, 0.65, 1)
    local roomLabel = self.detectedRoom and ("  •  " .. self.detectedRoom.title) or ""
    love.graphics.printf(
        string.format("Gevangen: %d/19   •   Vallen: %d%s", caught, traps, roomLabel),
        100,
        454,
        pillW - 8,
        "center"
    )

    if caught > 0 then
        local hotOrch = (self.hotzones.hoveredId == "open_orch")
        love.graphics.setColor(hotOrch and 0.25 or 0.16, hotOrch and 0.52 or 0.34, hotOrch and 0.28 or 0.20, 0.95)
        love.graphics.rectangle("fill", 466, 449, 84, 24, 5, 5)
        love.graphics.setColor(0.65, 0.95, 0.55, 1)
        love.graphics.rectangle("line", 466, 449, 84, 24, 5, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Orkest", 466, 454, 84, "center")
    end

    -- Draw Mouse-Detector TV Scanner following cursor
    if (self.scannerVisible or self.touchSelectedRoomId) and vx and vy then
        local gg = Assets.getDxr("ggmdmenu")
        local castId = self.detectedRoom and 2 or 1
        local cast = gg and gg.casts[castId]
        if cast and cast.image then
            local img = Assets.getImage(cast.image, "nearest")
            if img then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(img, vx - (cast.reg_x or 36), vy - (cast.reg_y or 20))
            end
        end
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
    end
    love.graphics.pop()
end

return HotelHub
