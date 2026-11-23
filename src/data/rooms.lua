-- Static metadata for the 20 hotel rooms (matching GGMDMENU Frame 14) and 19 instruments.

local Rooms = {}

-- Ordered in GGMDMENU STXT#42 roomlist order (channels 5..24 in Frame 14)
Rooms.LIST = {
    { id = "artist",   title = "Atelier",               x = 53,  y = 107, w = 91,  h = 67, mov = "artist",   dxr = "artist",   startsnd = "artist" },
    { id = "farmer",   title = "Boerenkamer",           x = 166, y = 104, w = 91,  h = 68, mov = "farmer",   dxr = "farmer",   startsnd = "farmer" },
    { id = "witches",  title = "Heksenkamer",           x = 278, y = 104, w = 93,  h = 68, mov = "witch",    dxr = "witches",  startsnd = "witches" },
    { id = "plumber",  title = "Loodgieterskamer",      x = 391, y = 105, w = 91,  h = 67, mov = "plumber",  dxr = "plumber",  startsnd = "plumber" },
    { id = "madsci",   title = "Laboratorium",          x = 506, y = 105, w = 91,  h = 67, mov = "madsci",   dxr = "madsci",   startsnd = "madsci" },

    { id = "newlywed", title = "Bruidssuite",           x = 50,  y = 188, w = 117, h = 67, mov = "newlywed", dxr = "newlywed", startsnd = "newlywed" },
    { id = "presbed",  title = "Presidentiële Slaapkamer", x = 188, y = 190, w = 122, h = 67, mov = "presbed",  dxr = "presbed",  startsnd = "presbed" },
    { id = "presliv",  title = "Presidentiële Salon",   x = 329, y = 191, w = 122, h = 67, mov = "presliv",  dxr = "presliv",  startsnd = "presliv" },
    { id = "ballroom", title = "Balzaal",               x = 471, y = 190, w = 121, h = 67, mov = "dance",    dxr = "ballroom", startsnd = "ballroom" },

    { id = "business", title = "Zakenkamer",            x = 47,  y = 277, w = 86,  h = 67, mov = "business", dxr = "business", startsnd = "business" },
    { id = "playroom", title = "Speelkamer",            x = 151, y = 279, w = 91,  h = 67, mov = "playroom", dxr = "playroom", startsnd = "playroom" },
    { id = "slobs",    title = "Rommelkamer",           x = 264, y = 278, w = 104, h = 67, mov = "slob",     dxr = "slobs",    startsnd = "slobs" },
    { id = "bathroom", title = "Badkamer",              x = 393, y = 277, w = 91,  h = 67, mov = "bathroom", dxr = "bathroom", startsnd = "bathroom" },
    { id = "exercise", title = "Fitnessruimte",         x = 505, y = 277, w = 91,  h = 67, mov = "exercise", dxr = "exercise", startsnd = "exercise" },

    { id = "library",  title = "Leeszaal",              x = 49,  y = 364, w = 91,  h = 67, mov = "library",  dxr = "library",  startsnd = "library" },
    { id = "dining",   title = "Eetkamer",              x = 159, y = 363, w = 91,  h = 67, mov = "dining",   dxr = "dining",   startsnd = "dining" },
    { id = "kitchen",  title = "Keuken",                x = 277, y = 364, w = 91,  h = 67, mov = "kitchen",  dxr = "kitchen",  startsnd = "kitchen" },
    { id = "bar",      title = "Bar",                   x = 391, y = 365, w = 91,  h = 67, mov = "bar",      dxr = "bar",      startsnd = "bar" },
    { id = "snooker",  title = "Biljartzaal",           x = 505, y = 364, w = 91,  h = 67, mov = "snooker",  dxr = "snooker",  startsnd = "snooker" },

    { id = "attic",    title = "Zolder",                x = 40,  y = 18,  w = 562, h = 67, mov = nil,        dxr = "attic",    startsnd = nil },
}

Rooms.BY_ID = {}
for _, r in ipairs(Rooms.LIST) do
    Rooms.BY_ID[r.id] = r
end

Rooms.INSTRUMENTS = {
    { id = "drums",    name = "Drumstel",      solo = "drums" },
    { id = "bass",     name = "Contrabas",     solo = "bass" },
    { id = "trum1",    name = "Trompet 1",     solo = "trump1" },
    { id = "trum2",    name = "Trompet 2",     solo = "trump2" },
    { id = "trom1",    name = "Trombone 1",    solo = "tromb1" },
    { id = "trom2",    name = "Trombone 2",    solo = "tromb2" },
    { id = "guitar",   name = "Gitaar",        solo = "guitar" },
    { id = "flute",    name = "Dwarsfluit",    solo = "flute" },
    { id = "clar1",    name = "Klarinet 1",    solo = "clarin1" },
    { id = "clar2",    name = "Klarinet 2",    solo = "clarin2" },
    { id = "congas",   name = "Conga's",       solo = "congas" },
    { id = "piano",    name = "Piano",         solo = "piano" },
    { id = "tenor1",   name = "Tenorsax 1",    solo = "tenor1" },
    { id = "tenor2",   name = "Tenorsax 2",    solo = "tenor2" },
    { id = "tenor3",   name = "Tenorsax 3",    solo = "tenor3" },
    { id = "alto1",    name = "Altsax 1",      solo = "alto1" },
    { id = "alto2",    name = "Altsax 2",      solo = "alto2" },
    { id = "barit",    name = "Baritonsax",    solo = "baritone" },
    { id = "vibes",    name = "Vibrafoon",     solo = "vibes" },
}

return Rooms
