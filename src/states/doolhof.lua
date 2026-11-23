-- Bonus Mode 1: Het Muizendoolhof (DOOLHOF.EXE).
-- Guide 10 green mice from (0,0) to any of the 3 corner cheeses and back to the hole
-- while dodging 3 porters, 2 cats, and 1 angry hotel guest on a 25x25 quadrant maze.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local ConfirmDialog = require("src.core.confirm_dialog")
local Cursor = require("src.core.cursor")
local Hotzone = require("src.core.hotzone")
local SceneManager = require("src.core.scene_manager")

local Doolhof = {}

local GRID_N = 25
local CELL_SIZE = 16
local GRID_ORIGIN_X = 112
local GRID_ORIGIN_Y = 40
local TOTAL_MICE = 10

local PLAYER_SPEED = 96
local SPAWN_GRACE_SECONDS = 1.2
local COMMOTION_DURATION = 0.9
local COLLISION_RADIUS = 11

local CENTER_H_DIVIDER = "SSOSSOOSSSSSSSOSSSSOSSSOS"
local CENTER_V_DIVIDER = "SOOSSOOSSSSSSSOOSSOOSOSOS"

local QUADRANT_CENTERS = {
    tl = { x = 208, y = 136 },
    bl = { x = 208, y = 344 },
    tr = { x = 416, y = 136 },
    br = { x = 416, y = 344 },
}

local CHEESE_CORNERS = {
    { col = 24, row = 0, cast = 93 },
    { col = 24, row = 24, cast = 94 },
    { col = 0, row = 24, cast = 95 },
}

local COMMOTION_CASTS = { 160, 161, 162, 163 }

local function cellCenter(col, row)
    return GRID_ORIGIN_X + col * CELL_SIZE + CELL_SIZE * 0.5,
           GRID_ORIGIN_Y + row * CELL_SIZE + CELL_SIZE * 0.5
end

local function parseWallLines(text)
    local rows = {}
    for line in (tostring(text or "") .. "\n"):gmatch("([^\r\n]+)") do
        local trimmed = line:gsub("%s+", "")
        if #trimmed >= 12 then
            table.insert(rows, trimmed)
        end
    end
    return rows
end

local function drawCastAt(score, castId, x, y, sx, sy)
    local cast = score and score.casts and score.casts[castId]
    if not cast or not cast.image then return end
    local img = Assets.getImage(cast.image, "nearest")
    if not img then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, sx or 1, sy or sx or 1, cast.reg_x or 0, cast.reg_y or 0)
end

local function shuffleCopy(list)
    local t = {}
    for i, v in ipairs(list) do t[i] = v end
    for i = #t, 2, -1 do
        local j = love.math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function Doolhof:enter()
    Cursor.reset()
    AudioQueue.stopAll()
    self.score = Assets.getDxr("doolhof")
    self:startNewRound()
end

function Doolhof:exit()
    AudioQueue.stopAll()
    Cursor.reset()
end

function Doolhof:isWall(col, row)
    if col < 0 or col >= GRID_N or row < 0 or row >= GRID_N then
        return true
    end
    return self.walls[row] and self.walls[row][col] == true
end

function Doolhof:buildMazeFromQuadrants(picks)
    local walls = {}
    for r = 0, GRID_N - 1 do
        walls[r] = {}
        for c = 0, GRID_N - 1 do
            walls[r][c] = false
        end
    end

    local function fillQuad(qIdx, rowOff, colOff)
        local cast = self.score and self.score.casts and self.score.casts[qIdx + 25]
        local lines = parseWallLines(cast and cast.text)
        for r = 0, 11 do
            local line = lines[r + 1] or "OOOOOOOOOOOO"
            for c = 0, 11 do
                walls[rowOff + r][colOff + c] = (line:sub(c + 1, c + 1) == "S")
            end
        end
    end

    fillQuad(picks.tl, 0, 0)
    fillQuad(picks.bl, 13, 0)
    fillQuad(picks.tr, 0, 13)
    fillQuad(picks.br, 13, 13)

    for i = 0, GRID_N - 1 do
        walls[12][i] = (CENTER_H_DIVIDER:sub(i + 1, i + 1) == "S")
        walls[i][12] = (CENTER_V_DIVIDER:sub(i + 1, i + 1) == "S")
    end

    -- Ensure spawn hole and 3 cheese corners are always open
    walls[0][0] = false
    walls[0][24] = false
    walls[24][24] = false
    walls[24][0] = false
    return walls
end

function Doolhof:isMazeConnected()
    local visited = {}
    local queue = { { c = 0, r = 0 } }
    visited[0] = true
    local head = 1
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        for _, d in ipairs(dirs) do
            local nc, nr = cur.c + d[1], cur.r + d[2]
            if not self:isWall(nc, nr) then
                local key = nr * GRID_N + nc
                if not visited[key] then
                    visited[key] = true
                    table.insert(queue, { c = nc, r = nr })
                end
            end
        end
    end
    for _, ch in ipairs(CHEESE_CORNERS) do
        if not visited[ch.row * GRID_N + ch.col] then
            return false
        end
    end
    return true
end

function Doolhof:generateMaze()
    local pool = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
    local bestPicks = { tl = 1, bl = 6, tr = 11, br = 16 }
    for _ = 1, 30 do
        local shuffled = shuffleCopy(pool)
        local picks = { tl = shuffled[1], bl = shuffled[2], tr = shuffled[3], br = shuffled[4] }
        self.quads = picks
        self.walls = self:buildMazeFromQuadrants(picks)
        bestPicks = picks
        if self:isMazeConnected() then
            return
        end
    end
    self.quads = bestPicks
    self.walls = self:buildMazeFromQuadrants(bestPicks)
end

function Doolhof:findNearestOpenCell(targetCol, targetRow, minDistFromOrigin, occupied)
    local bestC, bestR, bestScore = nil, nil, 999999
    for r = 0, GRID_N - 1 do
        for c = 0, GRID_N - 1 do
            local key = r * GRID_N + c
            local originDist = c + r
            if not self:isWall(c, r) and originDist >= (minDistFromOrigin or 10) and not occupied[key] then
                local d = math.abs(c - targetCol) + math.abs(r - targetRow)
                if d < bestScore then
                    bestScore = d
                    bestC, bestR = c, r
                end
            end
        end
    end
    if bestC then
        occupied[bestR * GRID_N + bestC] = true
        return bestC, bestR
    end
    return 12, 12
end

function Doolhof:spawnEnemies()
    local specs = {
        { kind = "porter", cast = 70, speed = 62, targetC = 22, targetR = 2 },
        { kind = "porter", cast = 70, speed = 62, targetC = 22, targetR = 22 },
        { kind = "porter", cast = 70, speed = 62, targetC = 2, targetR = 22 },
        { kind = "cat", cast = 56, speed = 58, targetC = 14, targetR = 8 },
        { kind = "cat", cast = 56, speed = 58, targetC = 8, targetR = 16 },
        { kind = "guest", cast = 53, speed = 66, targetC = 18, targetR = 16 },
    }
    local occupied = {}
    self.enemies = {}
    for _, sp in ipairs(specs) do
        local c, r = self:findNearestOpenCell(sp.targetC, sp.targetR, 10, occupied)
        local x, y = cellCenter(c, r)
        local enemy = {
            kind = sp.kind,
            cast = sp.cast,
            speed = sp.speed,
            col = c,
            row = r,
            x = x,
            y = y,
            dirX = 0,
            dirY = 0,
            targetCol = c,
            targetRow = r,
        }
        self:pickEnemyDirection(enemy)
        table.insert(self.enemies, enemy)
    end
end

function Doolhof:spawnPlayerMouse()
    local x, y = cellCenter(0, 0)
    self.player = {
        col = 0,
        row = 0,
        targetCol = 0,
        targetRow = 0,
        x = x,
        y = y,
        dirX = 0,
        dirY = 0,
        wantX = 0,
        wantY = 0,
        carryingCheese = false,
        spawnGrace = SPAWN_GRACE_SECONDS,
    }
end

function Doolhof:resetCheeses()
    self.cheeses = {}
    for _, ch in ipairs(CHEESE_CORNERS) do
        table.insert(self.cheeses, {
            col = ch.col,
            row = ch.row,
            cast = ch.cast,
            available = true,
        })
    end
end

function Doolhof:startNewRound()
    self.mode = "play"
    self.savedCount = 0
    self.caughtCount = 0
    self.currentMouseIdx = 1
    self.commotionTimer = 0
    self.commotionX = 320
    self.commotionY = 240
    self.heldDir = nil
    self.swipeStart = nil
    self.miceStatus = {}
    for i = 1, TOTAL_MICE do
        self.miceStatus[i] = (i == 1) and "active" or "waiting"
    end

    self:generateMaze()
    self:resetCheeses()
    self:spawnPlayerMouse()
    self:spawnEnemies()
    self:buildHotzones()
end

function Doolhof:buildHotzones()
    self.hotzones = Hotzone.new()

    local function addSteerZone(id, x, y, w, h, dx, dy)
        self.hotzones:add({
            id = id,
            x = x,
            y = y,
            w = w,
            h = h,
            steerX = dx,
            steerY = dy,
            onClick = function()
                if self.mode == "play" then
                    self:setDesiredDir(dx, dy)
                end
            end,
        })
    end

    -- Right-sidebar D-pad (fits cleanly right of c_68 border x=544)
    addSteerZone("dpad_up",    578, 174, 28, 28,  0, -1)
    addSteerZone("dpad_left",  549, 204, 28, 28, -1,  0)
    addSteerZone("dpad_right", 607, 204, 28, 28,  1,  0)
    addSteerZone("dpad_down",  578, 234, 28, 28,  0,  1)

    self.hotzones:add({
        id = "pause_btn",
        x = 550,
        y = 286,
        w = 84,
        h = 30,
        onClick = function()
            self:togglePause()
        end,
    })

    self.hotzones:add({
        id = "quit_btn",
        x = 550,
        y = 324,
        w = 84,
        h = 30,
        onClick = function()
            if self.mode == "gameover" then
                SceneManager.switch(App.states.launcher)
            else
                self:promptExit()
            end
        end,
    })

    -- Game-over summary card buttons (over c_83 replay maze & green exit arrow)
    self.hotzones:add({
        id = "gameover_replay",
        x = 220,
        y = 290,
        w = 56,
        h = 48,
        enabled = false,
        onClick = function()
            if self.mode == "gameover" then
                self:startNewRound()
            end
        end,
    })
    self.hotzones:add({
        id = "gameover_exit",
        x = 365,
        y = 290,
        w = 64,
        h = 48,
        enabled = false,
        onClick = function()
            if self.mode == "gameover" then
                SceneManager.switch(App.states.launcher)
            end
        end,
    })
end

function Doolhof:syncGameoverZones()
    local isOver = (self.mode == "gameover")
    for _, z in ipairs(self.hotzones.zones) do
        if z.id == "gameover_replay" or z.id == "gameover_exit" then
            z.enabled = isOver
        end
    end
end

function Doolhof:setDesiredDir(dx, dy)
    if not self.player then return end
    self.player.wantX = dx
    self.player.wantY = dy
end

function Doolhof:togglePause()
    if self.mode == "play" then
        self.mode = "paused"
    elseif self.mode == "paused" then
        self.mode = "play"
    end
end

function Doolhof:promptExit()
    local prevMode = self.mode
    if self.mode == "play" then
        self.mode = "paused"
    end
    SceneManager.setOverlay(ConfirmDialog, {
        title = "Muizendoolhof verlaten",
        message = "Wil je terug naar het hoofdmenu?",
        buttons = {
            {
                label = "Ja",
                key = "return",
                action = function()
                    SceneManager.clearOverlay()
                    SceneManager.switch(App.states.launcher)
                end,
            },
            {
                label = "Nee",
                key = "escape",
                action = function()
                    SceneManager.clearOverlay()
                    if prevMode == "play" then
                        self.mode = "play"
                    end
                end,
            },
        },
    })
end

function Doolhof:advanceToNextMouse()
    if self.currentMouseIdx >= TOTAL_MICE then
        self.mode = "gameover"
        self:syncGameoverZones()
        return
    end
    self.currentMouseIdx = self.currentMouseIdx + 1
    self.miceStatus[self.currentMouseIdx] = "active"
    self.mode = "play"
    self:resetCheeses()
    self:spawnPlayerMouse()
end

function Doolhof:stepGridEntity(ent, speed, dt, onReachCellCenter)
    local rem = speed * dt
    while rem > 0 do
        if ent.dirX == 0 and ent.dirY == 0 then
            if onReachCellCenter then
                onReachCellCenter(ent)
            end
            if ent.dirX == 0 and ent.dirY == 0 then
                break
            end
        end

        local tx, ty = cellCenter(ent.targetCol, ent.targetRow)
        local dx = tx - ent.x
        local dy = ty - ent.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= 0.001 then
            ent.x, ent.y = tx, ty
            ent.col, ent.row = ent.targetCol, ent.targetRow
            if onReachCellCenter then
                onReachCellCenter(ent)
            end
            if ent.dirX == 0 and ent.dirY == 0 then
                break
            end
            local nc = ent.col + ent.dirX
            local nr = ent.row + ent.dirY
            if self:isWall(nc, nr) then
                ent.dirX, ent.dirY = 0, 0
                break
            end
            ent.targetCol = nc
            ent.targetRow = nr
        elseif rem >= dist then
            ent.x, ent.y = tx, ty
            ent.col, ent.row = ent.targetCol, ent.targetRow
            rem = rem - dist
            if onReachCellCenter then
                onReachCellCenter(ent)
            end
            if ent.dirX ~= 0 or ent.dirY ~= 0 then
                local nc = ent.col + ent.dirX
                local nr = ent.row + ent.dirY
                if self:isWall(nc, nr) then
                    ent.dirX, ent.dirY = 0, 0
                    break
                end
                ent.targetCol = nc
                ent.targetRow = nr
            end
        else
            local inv = rem / dist
            ent.x = ent.x + dx * inv
            ent.y = ent.y + dy * inv
            rem = 0
        end
    end
end

function Doolhof:handlePlayerAtCell(p)
    -- Check cheese pickup
    if not p.carryingCheese then
        for _, ch in ipairs(self.cheeses) do
            if ch.available and p.col == ch.col and p.row == ch.row then
                ch.available = false
                p.carryingCheese = true
                AudioQueue.playSfx("dxr/doolhof/sounds/s_191.wav", 0.85)
                break
            end
        end
    elseif p.col == 0 and p.row == 0 then
        -- Returned home with cheese!
        AudioQueue.playSfx("dxr/doolhof/sounds/s_198.wav", 0.8)
        AudioQueue.playSfx("dxr/doolhof/sounds/s_197.wav", 0.9)
        self.miceStatus[self.currentMouseIdx] = "saved"
        self.savedCount = self.savedCount + 1
        self:advanceToNextMouse()
        return
    end

    if (p.wantX ~= 0 or p.wantY ~= 0) and not self:isWall(p.col + p.wantX, p.row + p.wantY) then
        p.dirX = p.wantX
        p.dirY = p.wantY
    elseif (p.dirX ~= 0 or p.dirY ~= 0) and self:isWall(p.col + p.dirX, p.row + p.dirY) then
        p.dirX = 0
        p.dirY = 0
    end
end

function Doolhof:pickEnemyDirection(e)
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local options = {}
    local nonReverse = {}
    for _, d in ipairs(dirs) do
        local nc = e.col + d[1]
        local nr = e.row + d[2]
        local inSpawnSafe = (nc <= 1 and nr <= 1)
        if not self:isWall(nc, nr) and not inSpawnSafe then
            table.insert(options, d)
            if not (d[1] == -e.dirX and d[2] == -e.dirY) then
                table.insert(nonReverse, d)
            end
        end
    end

    local pool = (#nonReverse > 0) and nonReverse or options
    if #pool == 0 then
        -- Fallback: allow leaving spawn safe zone if trapped
        for _, d in ipairs(dirs) do
            if not self:isWall(e.col + d[1], e.row + d[2]) then
                table.insert(pool, d)
            end
        end
    end
    if #pool == 0 then
        e.dirX, e.dirY = 0, 0
        return
    end

    local chosen = pool[love.math.random(1, #pool)]
    if self.player and self.player.spawnGrace <= 0 then
        local manhattan = math.abs(e.col - self.player.col) + math.abs(e.row - self.player.row)
        if manhattan <= 8 and love.math.random() < 0.55 then
            local bestD = chosen
            local bestDist = 999999
            for _, d in ipairs(pool) do
                local dist = math.abs((e.col + d[1]) - self.player.col) + math.abs((e.row + d[2]) - self.player.row)
                if dist < bestDist then
                    bestDist = dist
                    bestD = d
                end
            end
            chosen = bestD
        end
    end
    e.dirX, e.dirY = chosen[1], chosen[2]
end

function Doolhof:triggerCommotion()
    local sfx = (love.math.random(1, 2) == 1) and "dxr/doolhof/sounds/s_192.wav" or "dxr/doolhof/sounds/s_193.wav"
    AudioQueue.playSfx(sfx, 0.85)
    AudioQueue.playSfx("dxr/doolhof/sounds/s_196.wav", 0.85)
    self.mode = "commotion"
    self.commotionTimer = 0
    self.commotionX = self.player.x
    self.commotionY = self.player.y
end

function Doolhof:update(dt)
    if self.mode == "paused" or self.mode == "gameover" then
        return
    end

    if self.mode == "commotion" then
        self.commotionTimer = self.commotionTimer + dt
        if self.commotionTimer >= COMMOTION_DURATION then
            self.miceStatus[self.currentMouseIdx] = "caught"
            self.caughtCount = self.caughtCount + 1
            self:advanceToNextMouse()
        end
        return
    end

    if self.player.spawnGrace > 0 then
        self.player.spawnGrace = math.max(0, self.player.spawnGrace - dt)
    end

    -- Allow instant 180-degree reversal mid-corridor
    local p = self.player
    if (p.dirX ~= 0 or p.dirY ~= 0) and (p.wantX == -p.dirX and p.wantY == -p.dirY) then
        p.dirX, p.dirY = p.wantX, p.wantY
        local oldTargetC, oldTargetR = p.targetCol, p.targetRow
        p.targetCol, p.targetRow = p.col, p.row
        p.col, p.row = oldTargetC, oldTargetR
    end

    self:stepGridEntity(p, PLAYER_SPEED, dt, function(ent)
        self:handlePlayerAtCell(ent)
    end)

    if self.mode ~= "play" then
        return
    end

    for _, e in ipairs(self.enemies) do
        self:stepGridEntity(e, e.speed, dt, function(ent)
            self:pickEnemyDirection(ent)
        end)

        if self.player.spawnGrace <= 0 then
            local dx = self.player.x - e.x
            local dy = self.player.y - e.y
            if (dx * dx + dy * dy) < (COLLISION_RADIUS * COLLISION_RADIUS) then
                self:triggerCommotion()
                return
            end
        end
    end
end

function Doolhof:mousemoved(vx, vy)
    if self.swipeStart and self.mode == "play" then
        local dx = vx - self.swipeStart.x
        local dy = vy - self.swipeStart.y
        if math.abs(dx) >= 18 or math.abs(dy) >= 18 then
            if math.abs(dx) > math.abs(dy) then
                self:setDesiredDir(dx > 0 and 1 or -1, 0)
            else
                self:setDesiredDir(0, dy > 0 and 1 or -1)
            end
            self.swipeStart = { x = vx, y = vy }
        end
    end
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function Doolhof:mousepressed(vx, vy, button)
    if button ~= 1 then return end
    local hit = self.hotzones:click(vx, vy)
    if hit and hit.steerX then
        self.heldDir = { x = hit.steerX, y = hit.steerY }
        return
    end
    if not hit and self.mode == "play"
        and vx >= GRID_ORIGIN_X and vx < (GRID_ORIGIN_X + GRID_N * CELL_SIZE)
        and vy >= GRID_ORIGIN_Y and vy < (GRID_ORIGIN_Y + GRID_N * CELL_SIZE)
    then
        self.swipeStart = { x = vx, y = vy }
    end
end

function Doolhof:mousereleased()
    self.heldDir = nil
    self.swipeStart = nil
end

function Doolhof:keypressed(key)
    if key == "up" or key == "w" then
        self:setDesiredDir(0, -1)
        return true
    elseif key == "down" or key == "s" then
        self:setDesiredDir(0, 1)
        return true
    elseif key == "left" or key == "a" then
        self:setDesiredDir(-1, 0)
        return true
    elseif key == "right" or key == "d" then
        self:setDesiredDir(1, 0)
        return true
    elseif key == "p" or key == "space" then
        if self.mode == "play" or self.mode == "paused" then
            self:togglePause()
            return true
        end
    elseif key == "r" and self.mode == "gameover" then
        self:startNewRound()
        return true
    elseif key == "escape" then
        if self.mode == "gameover" then
            SceneManager.switch(App.states.launcher)
        else
            self:promptExit()
        end
        return true
    end
    return false
end

function Doolhof:drawSidebar(vx, vy)
    -- Left sidebar: 10 mice status (2x5 grid inside x=4..76)
    love.graphics.setColor(0.08, 0.10, 0.12, 0.85)
    love.graphics.rectangle("fill", 4, 24, 72, 272, 6, 6)
    love.graphics.setColor(0.45, 0.65, 0.45, 0.8)
    love.graphics.rectangle("line", 4, 24, 72, 272, 6, 6)

    for i = 1, TOTAL_MICE do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local ix = 22 + col * 34
        local iy = 56 + row * 44
        local st = self.miceStatus[i]
        local castId = 153
        if st == "saved" then
            castId = 154
        elseif st == "caught" then
            castId = 155
        end
        drawCastAt(self.score, castId, ix, iy, 0.72, 0.72)
        if st == "active" then
            love.graphics.setColor(0.35, 1, 0.45, 0.9)
            love.graphics.circle("line", ix, iy, 15)
        end
    end

    love.graphics.setColor(0.95, 0.92, 0.68, 1)
    love.graphics.printf(string.format("Gered\n%d/%d", self.savedCount, TOTAL_MICE), 6, 258, 68, "center")

    -- Right sidebar: prompt, touch D-pad, Pause & Stop buttons (x=548..636)
    love.graphics.setColor(0.08, 0.10, 0.12, 0.88)
    love.graphics.rectangle("fill", 547, 74, 90, 294, 6, 6)
    love.graphics.setColor(0.45, 0.65, 0.45, 0.8)
    love.graphics.rectangle("line", 547, 74, 90, 294, 6, 6)

    love.graphics.setColor(0.95, 0.92, 0.68, 1)
    local hint = (self.player and self.player.carryingCheese) and "Terug naar\nhet hol!" or "Pak een\nkaasje!"
    love.graphics.printf(hint, 549, 86, 86, "center")
    love.graphics.setColor(0.75, 0.82, 0.78, 0.9)
    love.graphics.printf(string.format("Muis %d/%d", self.currentMouseIdx, TOTAL_MICE), 549, 134, 86, "center")

    local dpadButtons = {
        { id = "dpad_up",    label = "^", x = 578, y = 174 },
        { id = "dpad_left",  label = "<", x = 549, y = 204 },
        { id = "dpad_right", label = ">", x = 607, y = 204 },
        { id = "dpad_down",  label = "v", x = 578, y = 234 },
    }
    for _, b in ipairs(dpadButtons) do
        local hot = (self.hotzones.hoveredId == b.id)
        love.graphics.setColor(hot and 0.28 or 0.18, hot and 0.52 or 0.24, hot and 0.30 or 0.22, 1)
        love.graphics.rectangle("fill", b.x, b.y, 28, 28, 5, 5)
        love.graphics.setColor(0.65, 0.85, 0.65, 1)
        love.graphics.rectangle("line", b.x, b.y, 28, 28, 5, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(b.label, b.x, b.y + 6, 28, "center")
    end

    for _, btn in ipairs({
        { id = "pause_btn", label = (self.mode == "paused") and "Verder" or "Pauze", y = 286 },
        { id = "quit_btn",  label = "Stoppen", y = 324 },
    }) do
        local hot = (self.hotzones.hoveredId == btn.id)
        love.graphics.setColor(hot and 0.28 or 0.16, hot and 0.46 or 0.20, hot and 0.30 or 0.24, 1)
        love.graphics.rectangle("fill", 550, btn.y, 84, 30, 5, 5)
        love.graphics.setColor(0.70, 0.82, 0.68, 1)
        love.graphics.rectangle("line", 550, btn.y, 84, 30, 5, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(btn.label, 550, btn.y + 8, 84, "center")
    end
end

function Doolhof:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0.06, 0.08, 0.10, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    -- Backdrop and maze frame + 4 randomized quadrants
    drawCastAt(self.score, 106, 320, 240)
    drawCastAt(self.score, 68, 318, 240)
    drawCastAt(self.score, self.quads.tl + 1, QUADRANT_CENTERS.tl.x, QUADRANT_CENTERS.tl.y)
    drawCastAt(self.score, self.quads.bl + 1, QUADRANT_CENTERS.bl.x, QUADRANT_CENTERS.bl.y)
    drawCastAt(self.score, self.quads.tr + 1, QUADRANT_CENTERS.tr.x, QUADRANT_CENTERS.tr.y)
    drawCastAt(self.score, self.quads.br + 1, QUADRANT_CENTERS.br.x, QUADRANT_CENTERS.br.y)

    -- Mouse hole at (0,0) and 3 corner cheeses
    drawCastAt(self.score, 96, 119, 39)
    for _, ch in ipairs(self.cheeses) do
        if ch.available then
            local cx, cy = cellCenter(ch.col, ch.row)
            drawCastAt(self.score, ch.cast, cx, cy)
        end
    end

    -- Enemies
    for _, e in ipairs(self.enemies) do
        drawCastAt(self.score, e.cast, e.x, e.y)
    end

    -- Player mouse or commotion cloud
    if self.mode == "commotion" then
        local idx = math.min(#COMMOTION_CASTS, math.floor((self.commotionTimer / COMMOTION_DURATION) * #COMMOTION_CASTS) + 1)
        drawCastAt(self.score, COMMOTION_CASTS[idx], self.commotionX, self.commotionY)
    elseif self.player and self.mode ~= "gameover" then
        local flash = self.player.spawnGrace > 0 and (math.floor(self.player.spawnGrace * 12) % 2 == 0)
        if not flash then
            local pCast = self.player.carryingCheese and 42 or 44
            drawCastAt(self.score, pCast, self.player.x, self.player.y)
        end
    end

    self:drawSidebar(vx, vy)

    if self.mode == "paused" then
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, 0, 640, 480)
        drawCastAt(self.score, 79, 320, 240)
        love.graphics.setColor(0.95, 0.92, 0.65, 1)
        love.graphics.printf("Druk op P of klik op 'Verder' om door te gaan", 120, 290, 400, "center")
    elseif self.mode == "gameover" then
        love.graphics.setColor(0, 0, 0, 0.62)
        love.graphics.rectangle("fill", 0, 0, 640, 480)
        drawCastAt(self.score, 83, 320, 240)

        love.graphics.setColor(0.15, 0.45, 0.15, 1)
        love.graphics.printf(string.format("%d / %d gered", self.savedCount, TOTAL_MICE), 300, 166, 130, "left")
        love.graphics.setColor(0.65, 0.10, 0.10, 1)
        love.graphics.printf(string.format("%d / %d gevangen", self.caughtCount, TOTAL_MICE), 300, 232, 130, "left")
        love.graphics.setColor(0.18, 0.22, 0.26, 1)
        love.graphics.printf("Opnieuw (R)", 200, 336, 96, "center")
        love.graphics.printf("Stoppen (Esc)", 346, 336, 102, "center")
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
        love.graphics.setColor(0, 1, 0, 0.25)
        for r = 0, GRID_N - 1 do
            for c = 0, GRID_N - 1 do
                if self:isWall(c, r) then
                    love.graphics.rectangle("fill", GRID_ORIGIN_X + c * CELL_SIZE, GRID_ORIGIN_Y + r * CELL_SIZE, CELL_SIZE, CELL_SIZE)
                end
            end
        end
    end

    love.graphics.pop()
end

return Doolhof
