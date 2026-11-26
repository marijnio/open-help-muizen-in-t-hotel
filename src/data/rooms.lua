-- Static metadata for the 20 hotel rooms (matching GGMDMENU Frame 14) and 19 instruments.

local Rooms = {}

-- Ordered in GGMDMENU STXT#42 roomlist order (channels 5..24 in Frame 14)
Rooms.LIST = {
    { id = "artist",   title = "Atelier",                   x = 43,  y = 83,  w = 110, h = 78, mov = "artist",   dxr = "artist",   startsnd = "artist" },
    { id = "farmer",   title = "Boerenkamer",               x = 161, y = 84,  w = 104, h = 77, mov = "farmer",   dxr = "farmer",   startsnd = "farmer" },
    { id = "witches",  title = "Heksenkamer",               x = 274, y = 83,  w = 100, h = 78, mov = "witch",    dxr = "witches",  startsnd = "witches" },
    { id = "plumber",  title = "Loodgieterskamer",          x = 383, y = 81,  w = 105, h = 80, mov = "plumber",  dxr = "plumber",  startsnd = "plumber" },
    { id = "madsci",   title = "Laboratorium",              x = 497, y = 81,  w = 105, h = 80, mov = "madsci",   dxr = "madsci",   startsnd = "madsci" },

    { id = "newlywed", title = "Bruidssuite",               x = 42,  y = 168, w = 131, h = 78, mov = "newlywed", dxr = "newlywed", startsnd = "newlywed" },
    { id = "presbed",  title = "Presidentiële Slaapkamer",  x = 183, y = 168, w = 132, h = 78, mov = "presbed",  dxr = "presbed",  startsnd = "presbed" },
    { id = "presliv",  title = "Presidentiële Salon",       x = 325, y = 169, w = 131, h = 79, mov = "presliv",  dxr = "presliv",  startsnd = "presliv" },
    { id = "ballroom", title = "Balzaal",                   x = 465, y = 169, w = 134, h = 80, mov = "dance",    dxr = "ballroom", startsnd = "ballroom" },

    { id = "business", title = "Zakenkamer",                x = 42,  y = 254, w = 96,  h = 78, mov = "business", dxr = "business", startsnd = "business" },
    { id = "playroom", title = "Speelkamer",                x = 145, y = 254, w = 102, h = 80, mov = "playroom", dxr = "playroom", startsnd = "playroom" },
    { id = "slobs",    title = "Rommelkamer",               x = 257, y = 254, w = 117, h = 79, mov = "slob",     dxr = "slobs",    startsnd = "slobs" },
    { id = "bathroom", title = "Badkamer",                  x = 383, y = 253, w = 106, h = 80, mov = "bathroom", dxr = "bathroom", startsnd = "bathroom" },
    { id = "exercise", title = "Fitnessruimte",             x = 498, y = 254, w = 103, h = 79, mov = "exercise", dxr = "exercise", startsnd = "exercise" },

    { id = "library",  title = "Leeszaal",                  x = 41,  y = 341, w = 105, h = 79, mov = "library",  dxr = "library",  startsnd = "library" },
    { id = "dining",   title = "Eetkamer",                  x = 154, y = 343, w = 101, h = 77, mov = "dining",   dxr = "dining",   startsnd = "dining" },
    { id = "kitchen",  title = "Keuken",                    x = 267, y = 341, w = 108, h = 79, mov = "kitchen",  dxr = "kitchen",  startsnd = "kitchen" },
    { id = "bar",      title = "Bar",                       x = 383, y = 342, w = 106, h = 77, mov = "bar",      dxr = "bar",      startsnd = "bar" },
    { id = "snooker",  title = "Biljartzaal",               x = 498, y = 340, w = 102, h = 80, mov = "snooker",  dxr = "snooker",  startsnd = "snooker" },

    { id = "attic",    title = "Zolder",                    x = 43,  y = 12,  w = 557, h = 64, mov = nil,        dxr = "attic",    startsnd = nil },
}

Rooms.BY_ID = {}
for _, r in ipairs(Rooms.LIST) do
    Rooms.BY_ID[r.id] = r
end

Rooms.TOTAL_MICE = 20
Rooms.STANDARD_MICE = 19
Rooms.ACTIVE_ROOM_SLOTS = 3

Rooms.BUILD_ORDERS = {
    [1] = {
        "bass", "drums", "trump1", "trump2", "trom1", "trom2", "guitar",
        "flute", "clarin1", "clarin2", "congas", "piano", "tenor1", "tenor2",
        "tenor3", "sax1", "sax2", "baritone", "vibes",
    },
    [2] = {
        "piano", "congas", "vibes", "clarin1", "clarin2", "flute", "bass",
        "guitar", "tenor1", "tenor2", "tenor3", "sax1", "sax2", "drums",
        "baritone", "trump1", "trump2", "trom1", "trom2",
    },
    [3] = {
        "trom1", "trom2", "flute", "piano", "trump1", "trump2", "drums",
        "tenor1", "tenor2", "tenor3", "sax1", "sax2", "bass", "clarin1",
        "clarin2", "baritone", "vibes", "guitar", "congas",
    },
}

local function randomInt(lo, hi)
    if love and love.math and love.math.random then
        return love.math.random(lo, hi)
    end
    return math.random(lo, hi)
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = randomInt(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

function Rooms.getBuildOrder(buildIndex)
    return Rooms.BUILD_ORDERS[buildIndex] or Rooms.BUILD_ORDERS[1]
end

function Rooms.getFoundInstrumentCount(session)
    if not session or type(session.foundInstruments) ~= "table" then
        return 0
    end
    local count = 0
    for id, v in pairs(session.foundInstruments) do
        if v and Rooms.INSTRUMENTS_BY_ID[id] then
            count = count + 1
        end
    end
    return count
end

function Rooms.getNextBuildInstrument(session)
    local buildIdx = session and session.buildIndex or 1
    local order = Rooms.getBuildOrder(buildIdx)
    local found = (session and type(session.foundInstruments) == "table") and session.foundInstruments or {}
    for _, id in ipairs(order) do
        if not found[id] and Rooms.INSTRUMENTS_BY_ID[id] then
            return Rooms.INSTRUMENTS_BY_ID[id]
        end
    end
    return Rooms.INSTRUMENTS_BY_ID[order[1]] or Rooms.INSTRUMENTS[1]
end

function Rooms.initSessionRooms(session)
    local standardIds = {}
    for _, r in ipairs(Rooms.LIST) do
        if r.id ~= "attic" then
            table.insert(standardIds, r.id)
        end
    end
    shuffle(standardIds)

    local queue = {}
    for i = 1, math.min(Rooms.STANDARD_MICE, #standardIds) do
        table.insert(queue, standardIds[i])
    end
    table.insert(queue, "attic")

    session.caughtMice = {}
    session.caughtCount = 0
    session.foundInstruments = {}
    session.lastInstrument = nil
    session.roomQueue = queue
    session.pendingInstrumentRoom = nil
    session.mouseRooms = {}
    for i = 1, math.min(Rooms.ACTIVE_ROOM_SLOTS, #standardIds) do
        session.mouseRooms[queue[i]] = true
    end
    session.activeMouseRoom = queue[1]
    return session
end

function Rooms.normalizeSession(session)
    if not session then return nil end

    local diff = math.floor(tonumber(session.difficulty) or 1)
    if diff < 1 then diff = 1 elseif diff > 3 then diff = 3 end
    session.difficulty = diff
    session.musicEnabled = (session.musicEnabled ~= false)

    local defaultTraps = ({ [1] = 10, [2] = 5, [3] = 0 })[diff] or 10
    if type(session.trapsLeft) ~= "number" or session.trapsLeft ~= session.trapsLeft then
        session.trapsLeft = defaultTraps
    else
        session.trapsLeft = math.max(0, math.floor(session.trapsLeft))
    end

    local buildIdx = math.floor(tonumber(session.buildIndex) or 1)
    if buildIdx < 1 or buildIdx > 3 then
        buildIdx = 1
    end
    session.buildIndex = buildIdx

    if type(session.seenIntros) ~= "table" then
        session.seenIntros = {}
    end

    local rawCaught = type(session.caughtMice) == "table" and session.caughtMice or {}
    local cleanCaught = {}
    local standardCaught = 0
    local atticCaught = false
    for id, v in pairs(rawCaught) do
        if v and Rooms.BY_ID[id] then
            cleanCaught[id] = true
            if id == "attic" then
                atticCaught = true
            else
                standardCaught = standardCaught + 1
            end
        end
    end
    local caughtCount = standardCaught + (atticCaught and 1 or 0)
    session.caughtMice = cleanCaught
    session.caughtCount = caughtCount

    local rawFound = type(session.foundInstruments) == "table" and session.foundInstruments or {}
    local cleanFound = {}
    local foundCount = 0
    for id, v in pairs(rawFound) do
        if v and Rooms.INSTRUMENTS_BY_ID[id] then
            cleanFound[id] = true
            foundCount = foundCount + 1
        end
    end

    if not Rooms.INSTRUMENTS_BY_ID[session.lastInstrument] then
        session.lastInstrument = nil
    end

    if type(session.pendingInstrumentRoom) == "string"
        and session.pendingInstrumentRoom ~= ""
        and standardCaught > 0
        and foundCount <= standardCaught
    then
        -- Preserve pending instrument room when a standard mouse was caught right before matching
    else
        session.pendingInstrumentRoom = nil
    end

    local expectedFound = math.max(0, math.min(Rooms.STANDARD_MICE, standardCaught - (session.pendingInstrumentRoom and 1 or 0)))
    local buildOrder = Rooms.getBuildOrder(buildIdx)
    if expectedFound == 0 then
        cleanFound = {}
        foundCount = 0
        session.lastInstrument = nil
    elseif foundCount < expectedFound then
        for _, id in ipairs(buildOrder) do
            if foundCount >= expectedFound then
                break
            end
            if Rooms.INSTRUMENTS_BY_ID[id] and not cleanFound[id] then
                cleanFound[id] = true
                foundCount = foundCount + 1
                if not session.lastInstrument then
                    session.lastInstrument = id
                end
            end
        end
    elseif foundCount > expectedFound then
        cleanFound = {}
        foundCount = 0
        for i = 1, expectedFound do
            local id = buildOrder[i]
            if id and Rooms.INSTRUMENTS_BY_ID[id] then
                cleanFound[id] = true
                foundCount = foundCount + 1
                session.lastInstrument = id
            end
        end
    end
    session.foundInstruments = cleanFound

    if caughtCount >= Rooms.TOTAL_MICE or atticCaught then
        session.roomQueue = {}
        session.activeMouseRoom = nil
        session.mouseRooms = {}
        return session
    end

    local neededStandard = math.max(0, Rooms.STANDARD_MICE - standardCaught)

    local cleanStandard = {}
    local seen = {}
    local function addStandard(id)
        if #cleanStandard >= neededStandard then return end
        if id and id ~= "attic" and Rooms.BY_ID[id] and not session.caughtMice[id] and not seen[id] then
            seen[id] = true
            table.insert(cleanStandard, id)
        end
    end

    if type(session.roomQueue) == "table" and #session.roomQueue > 0 then
        for _, id in ipairs(session.roomQueue) do
            addStandard(id)
        end
    elseif type(session.mouseRooms) == "table" then
        local legacyStandard = {}
        for _, r in ipairs(Rooms.LIST) do
            if r.id ~= "attic" and session.mouseRooms[r.id] == true and not session.caughtMice[r.id] then
                table.insert(legacyStandard, r.id)
            end
        end
        shuffle(legacyStandard)
        for _, id in ipairs(legacyStandard) do
            addStandard(id)
        end
    end

    if #cleanStandard < neededStandard then
        local remaining = {}
        for _, r in ipairs(Rooms.LIST) do
            if r.id ~= "attic" and not session.caughtMice[r.id] and not seen[r.id] then
                table.insert(remaining, r.id)
            end
        end
        shuffle(remaining)
        for _, id in ipairs(remaining) do
            addStandard(id)
        end
    end

    local queue = {}
    for _, id in ipairs(cleanStandard) do
        table.insert(queue, id)
    end
    table.insert(queue, "attic")
    session.roomQueue = queue

    local activeRooms = {}
    if #cleanStandard == 0 then
        activeRooms["attic"] = true
        session.mouseRooms = activeRooms
        session.activeMouseRoom = "attic"
    else
        local activeCount = 0
        local maxActive = math.min(Rooms.ACTIVE_ROOM_SLOTS, #cleanStandard)
        if type(session.mouseRooms) == "table" then
            for _, id in ipairs(cleanStandard) do
                if activeCount >= maxActive then
                    break
                end
                if session.mouseRooms[id] == true then
                    activeRooms[id] = true
                    activeCount = activeCount + 1
                end
            end
        end
        for _, id in ipairs(cleanStandard) do
            if activeCount >= maxActive then
                break
            end
            if not activeRooms[id] then
                activeRooms[id] = true
                activeCount = activeCount + 1
            end
        end
        session.mouseRooms = activeRooms
        if session.activeMouseRoom and activeRooms[session.activeMouseRoom] then
            -- Keep existing primary active room when still in shortlist
        else
            session.activeMouseRoom = cleanStandard[1]
        end
    end

    return session
end

function Rooms.isActiveMouseRoom(session, roomId)
    return session ~= nil and roomId ~= nil and type(session.mouseRooms) == "table" and session.mouseRooms[roomId] == true
end

function Rooms.markRoomCaught(session, roomId, pendingInstrumentRoom)
    if not session or not roomId or not Rooms.BY_ID[roomId] then
        return session and session.activeMouseRoom or nil
    end
    session.caughtMice = session.caughtMice or {}
    session.caughtMice[roomId] = true
    session.pendingInstrumentRoom = pendingInstrumentRoom
    session.mouseRooms = {}
    session.activeMouseRoom = nil

    if type(session.roomQueue) == "table" and #session.roomQueue > 0 then
        local remaining = {}
        for _, id in ipairs(session.roomQueue) do
            if id ~= "attic" and not session.caughtMice[id] then
                table.insert(remaining, id)
            end
        end
        shuffle(remaining)
        table.insert(remaining, "attic")
        session.roomQueue = remaining
    end

    Rooms.normalizeSession(session)
    return session.activeMouseRoom
end

-- Maps MUSIC/BUILD*.TXT instrument tokens -> canonical audio keys in manifest.lua
Rooms.BUILD_TO_INSTRUMENT = {
    trum1  = "trump1",
    trum2  = "trump2",
    clar1  = "clarin1",
    clar2  = "clarin2",
    alto1  = "sax1",
    alto2  = "sax2",
    barit  = "baritone",
    drums  = "drums",
    bass   = "bass",
    trom1  = "trom1",
    trom2  = "trom2",
    guitar = "guitar",
    flute  = "flute",
    congas = "congas",
    piano  = "piano",
    tenor1 = "tenor1",
    tenor2 = "tenor2",
    tenor3 = "tenor3",
    vibes  = "vibes",
}

function Rooms.normalizeInstrumentId(token)
    local k = string.lower(tostring(token or ""))
    return Rooms.BUILD_TO_INSTRUMENT[k] or k
end

-- 19 orchestra instruments matching solos/, music_build1..3/, INSTRUM.DXR, and ORCH.DXR
Rooms.INSTRUMENTS = {
    { id = "drums",    name = "Drumstel",      family = "drums",    instrumLabel = "drums",    loopLabel = "drumsloop",    orchChannel = 3 },
    { id = "bass",     name = "Contrabas",     family = "bass",     instrumLabel = "bass",     loopLabel = "bassloop",     orchChannel = 5 },
    { id = "trump1",   name = "Trompet 1",     family = "trumpet",  instrumLabel = "trump1",   loopLabel = "trump1loop",   orchChannel = 9 },
    { id = "trump2",   name = "Trompet 2",     family = "trumpet",  instrumLabel = "trump2",   loopLabel = "trump2loop",   orchChannel = 10 },
    { id = "trom1",    name = "Trombone 1",    family = "trombone", instrumLabel = "trom1",    loopLabel = "trom1loop",    orchChannel = 11 },
    { id = "trom2",    name = "Trombone 2",    family = "trombone", instrumLabel = "trom2",    loopLabel = "trom2loop",    orchChannel = 12 },
    { id = "guitar",   name = "Gitaar",        family = "guitar",   instrumLabel = "guitar",   loopLabel = "guitarloop",   orchChannel = 4 },
    { id = "flute",    name = "Dwarsfluit",    family = "flute",    instrumLabel = "flute",    loopLabel = "fluteloop",    orchChannel = 14 },
    { id = "clarin1",  name = "Klarinet 1",    family = "clarinet", instrumLabel = "clarin1",  loopLabel = "clarin1loop",  orchChannel = 7 },
    { id = "clarin2",  name = "Klarinet 2",    family = "clarinet", instrumLabel = "clarin2",  loopLabel = "clarin2loop",  orchChannel = 8 },
    { id = "congas",   name = "Conga's",       family = "congas",   instrumLabel = "congas",   loopLabel = "congasloop",   orchChannel = 2 },
    { id = "piano",    name = "Piano",         family = "piano",    instrumLabel = "piano",    loopLabel = "pianoloop",    orchChannel = 22 },
    { id = "tenor1",   name = "Tenorsax 1",    family = "sax",      instrumLabel = "tenor1",   loopLabel = "tenor1loop",   orchChannel = 15 },
    { id = "tenor2",   name = "Tenorsax 2",    family = "sax",      instrumLabel = "tenor2",   loopLabel = "tenor2loop",   orchChannel = 16 },
    { id = "tenor3",   name = "Tenorsax 3",    family = "sax",      instrumLabel = "tenor3",   loopLabel = "tenor3loop",   orchChannel = 17 },
    { id = "sax1",     name = "Altsax 1",      family = "sax",      instrumLabel = "sax1",     loopLabel = "sax1loop",     orchChannel = 19 },
    { id = "sax2",     name = "Altsax 2",      family = "sax",      instrumLabel = "sax2",     loopLabel = "sax2loop",     orchChannel = 20 },
    { id = "baritone", name = "Baritonsax",    family = "sax",      instrumLabel = "baritone", loopLabel = "baritoneloop", orchChannel = 18 },
    { id = "vibes",    name = "Vibrafoon",     family = "vibes",    instrumLabel = "vibes",    loopLabel = "vibesloop",    orchChannel = 23 },
}

Rooms.INSTRUMENTS_BY_ID = {}
for _, inst in ipairs(Rooms.INSTRUMENTS) do
    Rooms.INSTRUMENTS_BY_ID[inst.id] = inst
end

-- 11 clickable instrument families in INSTRUM.DXR Frame 4 ("select"), channels 7..17
Rooms.INSTRUM_FAMILIES = {
    { ch = 7,  family = "clarinet", label = "Klarinet",   hilite = 247, rejectLabel = "reject general", rejectSfx = "dxr/instrum/sounds/s_296.wav" },
    { ch = 8,  family = "trumpet",  label = "Trompet",    hilite = 256, rejectLabel = "reject trumpet", rejectSfx = "dxr/instrum/sounds/s_293.wav" },
    { ch = 9,  family = "bass",     label = "Contrabas",  hilite = 249, rejectLabel = "reject general", rejectSfx = "dxr/instrum/sounds/s_296.wav" },
    { ch = 10, family = "guitar",   label = "Gitaar",     hilite = 254, rejectLabel = "reject guitar",  rejectSfx = "dxr/instrum/sounds/s_294.wav" },
    { ch = 11, family = "sax",      label = "Saxofoon",   hilite = 255, rejectLabel = "reject general", rejectSfx = "dxr/instrum/sounds/s_296.wav" },
    { ch = 12, family = "piano",    label = "Piano",      hilite = nil, rejectLabel = "reject piano",   rejectSfx = "dxr/instrum/sounds/s_295.wav" },
    { ch = 13, family = "vibes",    label = "Vibrafoon",  hilite = 252, rejectLabel = "reject vibes",   rejectSfx = "dxr/instrum/sounds/s_296.wav" },
    { ch = 14, family = "trombone", label = "Trombone",   hilite = 253, rejectLabel = "reject general", rejectSfx = "dxr/instrum/sounds/s_296.wav" },
    { ch = 15, family = "flute",    label = "Dwarsfluit", hilite = 248, rejectLabel = "reject general", rejectSfx = "dxr/instrum/sounds/s_296.wav" },
    { ch = 16, family = "drums",    label = "Drumstel",   hilite = 251, rejectLabel = "reject general", rejectSfx = "dxr/instrum/sounds/s_296.wav" },
    { ch = 17, family = "congas",   label = "Conga's",    hilite = 250, rejectLabel = "reject general", rejectSfx = "dxr/instrum/sounds/s_296.wav" },
}

return Rooms
