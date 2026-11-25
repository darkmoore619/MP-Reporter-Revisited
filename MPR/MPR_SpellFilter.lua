--[[---------------------------------------------------------------------------
    MPR Spell Filter
    Lets the user choose, spell by spell, what MP Reporter announces.

    Storage: MPR.Settings["SPELL_FILTER"] holds only the DISABLED keys
    (key = true). Anything not in the table is reported, so new spells are
    on by default.

    Key formats:
        "Spell Name"     chat report (Self / Raid / Party)
        "D:Spell Name"   damage tick report
        "H:Spell Name"   heal report
        "L:Spell Name"   combined "applied on X, Y, Z" target list
        "SP:Spell Name"  spawn message
        "W:Spell Name"   whisper sent to the affected player
        "S:Spell Name"   /say when the aura lands on you
---------------------------------------------------------------------------]]

MPR_SpellFilter = CreateFrame("Frame", "MPR_SpellFilter", UIParent)

-- Spells whose combat log name we can't rely on, mapped to the checkbox key.
local KeyById = {
    [33786] = "Cyclone",
    [48477] = "Rebirth",
    [69381] = "Drums of the Wild",
}

--[[ Helpers used by MPR.lua ]]--

function MPR:IsSpellReported(key)
    if key == nil then return true end
    local filter = self.Settings and self.Settings["SPELL_FILTER"]
    if not filter then return true end
    return not filter[tostring(key)]
end

-- Names that share one checkbox (Horde Bloodlust is reported as Heroism).
local NameAlias = {["Bloodlust"] = "Heroism"}

function MPR:SpellKey(spellId)
    if type(spellId) ~= "number" then return spellId end
    local name = KeyById[spellId] or (GetSpellInfo(spellId))
    return NameAlias[name] or name
end

function MPR:WhisperSpell(key, ...)
    if self:IsSpellReported("W:"..tostring(key)) then
        self:Whisper(...)
    end
end

function MPR:SaySpell(key, ...)
    if self:IsSpellReported("S:"..tostring(key)) then
        self:Say(...)
    end
end

--[[---------------------------------------------------------------------------
    Spell IDs (for icons and tooltips)
    A number or a list of candidate IDs per spell name. Candidates are only
    accepted if the client confirms the ID has exactly that spell name, so a
    wrong guess can never show the wrong icon. Spells that are still unknown
    are learned from the combat log the first time they are seen.
---------------------------------------------------------------------------]]

local SpellIds = {
    ["Remorseless Winter"]          = 68981,
    ["Quake"]                       = 72262,
    ["Defile"]                      = 72762,
    ["Shadow Trap"]                 = 73529,
    ["Necrotic Plague"]             = 70337,
    ["Rune of Blood"]               = 72410,
    ["Vile Gas"]                    = 69240,
    ["Swarming Shadows"]            = 71264,
    ["Blistering Cold"]             = 70123,
    ["Frost Beacon"]                = 70126,
    ["Gas Spore"]                   = 69278,
    ["Fiery Combustion"]            = 74562,
    ["Soul Consumption"]            = 74792,
    ["Cleave Armor"]                = 74367,
    ["Enrage"]                      = 78722,
    ["Impaled"]                     = 69065,
    ["Dominate Mind"]               = 71289,
    ["Essence of the Blood Queen"]  = 71473,
    ["Frenzied Bloodthirst"]        = 70877,
    ["Uncontrollable Frenzy"]       = 70923,
    ["Pain and Suffering"]          = 72133,
    ["Instability"]                 = 69766,
    ["Chilled to the Bone"]         = 70106,
    ["Touch of Jaraxxus"]           = 66209,
    ["Unbound Plague"]              = 72854,
    ["Malleable Goo"]               = 70852,
    ["Slime Pool"]                  = 66883,
    ["Vengeful Shade"]              = 71426,
    ["Cyclone"]                     = 33786,
    ["Rebirth"]                     = 48477,
    ["Drums of the Wild"]           = 69381,
    ["Hand of Protection"]          = {1022, 5599, 10278},
    ["Blessing of Forgotten Kings"] = {69378},
    ["Runescroll of Fortitude"]     = {72588},
    ["Great Feast"]                 = {57301},
    ["Fish Feast"]                  = {57426},
    ["Ritual of Souls"]             = {29893},
    ["Ritual of Refreshment"]       = {43987},
    ["Dark Vortex"]                 = {66058, 67182, 67183, 67184},
    ["Light Vortex"]                = {66046, 67206, 67207, 67208},
    ["Soul Reaper"]                 = {69409, 73797, 73798, 73799},
    ["Volatile Ooze Adhesive"]      = {70447, 72836, 72837, 72838},
    ["Gaseous Bloat"]               = {70672, 72455, 72832, 72833},
    ["Unstable Ooze"]               = {69558, 72549, 72550},
    ["Unstable Ooze Explosion"]     = {69839, 73029, 73030, 73031},
    ["Incinerate Flesh"]            = {66237, 67049, 67050, 67051},
    ["Dark Martyrdom"]              = {70897, 71236},
    ["Shadow Cleave"]               = {70670, 72006, 72007},
    ["Deathchill Blast"]            = {71951, 72488, 72489, 72490},
    ["Vengeful Blast"]              = {71544, 72010, 72011, 72012},
    ["Choking Gas Explosion"]       = {71279, 72459, 72619, 72620},
    ["Frost Bomb"]                  = {69846, 70521, 72424},
    ["Trample"]                     = {66171, 66734, 67868, 67869},
}

-- IDs whose game name differs from the name the addon matches on.
local TrustedIds = {
    [69381] = true,  -- Drums of the Wild ("Gift of the Wild" in the client)
    [71426] = true,  -- Summon Vengeful Shade
    [74502] = true,  -- Enervating Brand
    [32182] = true,  -- Heroism (Alliance)
    [2825]  = true,  -- Bloodlust (Horde)
}

local function ResolveId(name)
    if tonumber(name) then return tonumber(name) end
    if name == "Heroism" then
        return (UnitFactionGroup("player") == "Horde") and 2825 or 32182
    end
    local ids = SpellIds[name]
    if type(ids) == "number" then ids = {ids} end
    if ids then
        for _, id in ipairs(ids) do
            if TrustedIds[id] then return id end
            local n = GetSpellInfo(id)
            if n and n == name then return id end
        end
    end
    local learned = MPR.Settings and MPR.Settings["SPELL_IDS"]
    return learned and learned[name] or nil
end

--[[---------------------------------------------------------------------------
    Catalog
    Two sides: "player" (spells cast by players) and "encounter" (boss
    abilities and the warnings the addon builds around them).
---------------------------------------------------------------------------]]

local SIDES = {
    player    = {title = "PLAYER SPELLS",            tag = "Player",    color = "55AAFF", full = "Player spell"},
    encounter = {title = "ENCOUNTER (BOSS) SPELLS",  tag = "Encounter", color = "FF5555", full = "Encounter (boss) spell"},
}

local WHAT_CAST   = "Announces when the boss casts it."
local WHAT_TARGET = "Announces which player it was cast on."
local WHAT_AURA   = "Announces which player received it."
local WHAT_STACKS = "Announces the stack count on the player."
local WHAT_LIST   = "One combined line listing every affected player."
local WHAT_AOE    = "One combined line listing everyone hit and the damage taken."

-- suffix colors (matches the Whisper / Say colors of the main options)
local SUFFIX_COLORS = {whisper = "DA70D6", say = "FFFFFF"}

local Catalog = {
    {side = "player", groups = {
        {title = "Chat: raid buffs & consumables", what = "Announces who casts it.", entries = {
            {key = "Blessing of Forgotten Kings"},
            {key = "Drums of the Wild"},
            {key = "Heroism", label = "Heroism / Bloodlust", what = "Announces the caster and how many players were affected. Covers Heroism (Alliance) and Bloodlust (Horde)."},
            {key = "Runescroll of Fortitude"},
        }},
        {title = "Chat: class abilities", entries = {
            {key = "Cyclone", what = "Announces who cycloned whom."},
            {key = "Hand of Protection", what = "Announces who casts it and on whom."},
            {key = "Rebirth", what = "Announces who resurrects whom (druid combat res)."},
        }},
        {title = "Chat: feasts & rituals", what = "Announces who prepares it and warns 30 seconds before it expires.", entries = {
            {key = "Fish Feast"}, {key = "Great Feast"}, {key = "Ritual of Refreshment"}, {key = "Ritual of Souls"},
        }},
    }},

    {side = "encounter", instances = {
        {name = "Trial of the Crusader", encounters = {
            {name = "Northrend Beasts", entries = {
                {key = "Slime Pool", suffix = "summon", what = "Announces when Acidmaw or Dreadscale spawns a Slime Pool."},
                {key = "Trample", suffix = "AOE", what = "Icehowl: "..WHAT_AOE},
            }},
            {name = "Lord Jaraxxus", entries = {
                {key = "Incinerate Flesh", what = WHAT_AURA},
                {key = "W:Touch of Jaraxxus", label = "Touch of Jaraxxus", suffix = "whisper", what = "Whispers 'Run away till debuff is gone!'."},
            }},
            {name = "Twin Val'kyr", entries = {
                {key = "Dark Vortex", what = WHAT_CAST},
                {key = "Light Vortex", what = WHAT_CAST},
            }},
        }},

        {name = "Icecrown Citadel", encounters = {
            {name = "Lord Marrowgar", entries = {
                {key = "L:Impaled", label = "Impaled", suffix = "list", what = WHAT_LIST},
                {key = "S:Impaled", label = "Impaled", suffix = "say", what = "You say 'Bone Spike on me!' in /say when you are impaled (needs the Say option)."},
            }},
            {name = "Lady Deathwhisper", entries = {
                {key = "Dark Martyrdom", suffix = "AOE", what = WHAT_AOE},
                {key = "Deathchill Blast", suffix = "AOE", what = WHAT_AOE},
                {key = "S:Dominate Mind", label = "Dominate Mind", suffix = "say", what = "You say 'Dominate Mind on me!' in /say (needs the Say option)."},
                {key = "Shadow Cleave", suffix = "AOE", what = WHAT_AOE},
                {key = "Vengeful Blast", suffix = "AOE", what = WHAT_AOE},
                {key = "Vengeful Shade", suffix = "summon", what = "Announces when a Vengeful Shade is summoned."},
            }},
            {name = "Deathbringer Saurfang", entries = {
                {key = "H:Rune of Blood", label = "Rune of Blood", suffix = "heal", what = "Reports each heal and the amount."},
                {key = "Rune of Blood", what = WHAT_TARGET},
            }},
            {name = "Festergut", entries = {
                {key = "L:Gas Spore", label = "Gas Spore", suffix = "list", what = WHAT_LIST},
                {key = "L:Vile Gas", label = "Vile Gas", suffix = "list", what = WHAT_LIST},
                {key = "Vile Gas", suffix = "single target", what = WHAT_TARGET},
            }},
            {name = "Rotface", entries = {
                {key = "Unstable Ooze", suffix = "stacks", what = WHAT_STACKS},
                {key = "Unstable Ooze Explosion", suffix = "AOE", what = WHAT_AOE},
                {key = "L:Vile Gas", label = "Vile Gas", suffix = "list", what = WHAT_LIST.." Heroic only (cast by Professor Putricide)."},
                {key = "Vile Gas", suffix = "single target", what = WHAT_TARGET.." Heroic only (cast by Professor Putricide)."},
            }},
            {name = "Professor Putricide", entries = {
                {key = "Choking Gas Explosion", suffix = "AOE", what = WHAT_AOE},
                {key = "Gaseous Bloat", what = WHAT_AURA},
                {key = "S:Gaseous Bloat", label = "Gaseous Bloat", suffix = "say", what = "You say 'Orange on me!' in /say (needs the Say option)."},
                {key = "W:Gaseous Bloat", label = "Gaseous Bloat", suffix = "whisper", what = "Whispers 'Kite it!'."},
                {key = "Malleable Goo", suffix = "AOE", what = WHAT_AOE},
                {key = "Unbound Plague", what = WHAT_AURA},
                {key = "Volatile Ooze Adhesive", what = WHAT_AURA},
                {key = "S:Volatile Ooze Adhesive", label = "Volatile Ooze Adhesive", suffix = "say", what = "You say 'Green on me!' in /say (needs the Say option)."},
            }},
            {name = "Blood-Queen Lana'thel", entries = {
                {key = "S:Essence of the Blood Queen", label = "Essence of the Blood Queen", suffix = "say", what = "You say 'I was biten!' in /say (needs the Say option)."},
                {key = "S:Frenzied Bloodthirst", label = "Frenzied Bloodthirst", suffix = "say", what = "You say 'I have to bite!!' in /say (needs the Say option)."},
                {key = "W:Frenzied Bloodthirst", label = "Frenzied Bloodthirst", suffix = "whisper", what = "Whispers 'You have to bite!'."},
                {key = "Swarming Shadows", what = WHAT_TARGET},
                {key = "W:Swarming Shadows", label = "Swarming Shadows", suffix = "whisper", what = "Whispers 'Run along walls!'."},
                {key = "Uncontrollable Frenzy", suffix = "failed bite", what = "Announces who failed to bite."},
            }},
            {name = "Sindragosa", entries = {
                {key = "Blistering Cold", suffix = "AOE", what = WHAT_AOE},
                {key = "W:Chilled to the Bone", label = "Chilled to the Bone", suffix = "whisper", what = "Whispers 'Stop attacking!' at 10 stacks."},
                {key = "Frost Bomb", suffix = "AOE", what = WHAT_AOE},
                {key = "L:Frost Beacon", label = "Frost Beacon", suffix = "list", what = WHAT_LIST},
                {key = "S:Frost Beacon", label = "Frost Beacon", suffix = "say", what = "You say 'Frost Beacon on me!' in /say (needs the Say option)."},
                {key = "W:Frost Beacon", label = "Frost Beacon", suffix = "whisper", what = "Whispers 'Run away from others!'."},
                {key = "W:Instability", label = "Instability", suffix = "whisper", what = "Whispers 'Stop casting!' at 8 stacks."},
            }},
            {name = "The Lich King", entries = {
                {key = "Defile", suffix = "AOE", what = WHAT_AOE},
                {key = "Necrotic Plague", what = WHAT_TARGET},
                {key = "D:Necrotic Plague", label = "Necrotic Plague", suffix = "damage", what = "Reports each damage tick and the amount."},
                {key = "W:Necrotic Plague", label = "Necrotic Plague", suffix = "whisper", what = "Whispers 'Run to a Shambling Horror!'."},
                {key = "W:Pain and Suffering", label = "Pain and Suffering", suffix = "whisper", what = "Whispers 'Spread!' at 5 stacks."},
                {key = "Quake", what = WHAT_CAST},
                {key = "Remorseless Winter", what = WHAT_CAST},
                {key = "Shadow Trap", suffix = "AOE", what = WHAT_AOE},
                {key = "SP:Shadow Trap", label = "Shadow Trap", suffix = "spawn", what = "Posts the spell link when a Shadow Trap spawns."},
                {key = "Soul Reaper", what = WHAT_TARGET},
            }},
        }},

        {name = "The Ruby Sanctum", encounters = {
            {name = "Saviana Ragefire", entries = {
                {key = "Enrage", what = WHAT_AURA},
            }},
            {name = "Baltharus the Warborn", entries = {
                {key = "W:74502", label = "Enervating Brand", suffix = "whisper", what = "Whispers 'Run away!' (spell ID 74502)."},
            }},
            {name = "General Zarithrian", entries = {
                {key = "Cleave Armor", suffix = "stacks", what = WHAT_STACKS},
            }},
            {name = "Halion", entries = {
                {key = "Fiery Combustion", what = WHAT_AURA},
                {key = "W:Fiery Combustion", label = "Fiery Combustion", suffix = "whisper", what = "Whispers 'Run to the wall!'."},
                {key = "Soul Consumption", what = WHAT_AURA},
                {key = "W:Soul Consumption", label = "Soul Consumption", suffix = "whisper", what = "Whispers 'Run to the wall!'."},
            }},
        }},
    }},
}

--[[ UI ]]--

local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local Rows = {}
local Wanted, WantedCount = {}, 0
local ROW_HEIGHT = 20

-- Dispel options are plain on/off settings (not spell filter keys)
local DispelOptions = {
    {setting = "REPORT_DISPELS",     text = "Dispels",      spellId = 527,   what = "Announces who dispels whom and which effect was removed."},
    {setting = "REPORT_MASSDISPELS", text = "Mass Dispels", spellId = 32375, what = "Also announces Mass Dispel casts. Needs Dispels to be checked as well."},
}
local DispelRows = {}

local function GetFilter()
    MPR.Settings["SPELL_FILTER"] = MPR.Settings["SPELL_FILTER"] or {}
    return MPR.Settings["SPELL_FILTER"]
end

local function HexToRGB(hex)
    return tonumber(hex:sub(1,2),16)/255, tonumber(hex:sub(3,4),16)/255, tonumber(hex:sub(5,6),16)/255
end

local function SetRows(side, enabled)
    local filter = GetFilter()
    for _, row in ipairs(Rows) do
        if not side or row.side == side then
            filter[row.filterKey] = (not enabled) and true or nil
        end
    end
    MPR_SpellFilter:Refresh()
end

function MPR_SpellFilter:Refresh()
    for _, row in ipairs(Rows) do
        row:SetChecked(MPR:IsSpellReported(row.filterKey))
        if not row.spellId then row.spellId = ResolveId(row.spellName) end
        local icon = row.spellId and select(3, GetSpellInfo(row.spellId))
        row.icon:SetTexture(icon or ICON_FALLBACK)
    end
    for _, cb in ipairs(DispelRows) do
        cb:SetChecked(MPR.Settings[cb.setting])
    end
end

function MPR_SpellFilter:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

local function ShowTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local id = row.spellId
    if id and GetSpellInfo(id) then
        GameTooltip:SetHyperlink("spell:"..id)
    else
        GameTooltip:AddLine(row.labelText, 1, 1, 1)
    end
    local side = SIDES[row.side]
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(side.full, HexToRGB(side.color))
    if row.context then GameTooltip:AddLine(row.context, 1, 0.82, 0) end
    if row.what then GameTooltip:AddLine(row.what, 1, 1, 1, true) end
    if id then
        GameTooltip:AddLine("Spell ID: "..id, 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Icon and description appear once the spell has been seen in combat.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

function MPR_SpellFilter:Initialize()
    local f = self
    f:Hide()
    f:SetWidth(416)
    f:SetHeight(440)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetPoint("TOPLEFT", MPR_Options, "TOPRIGHT", 0, 0)

    f:SetBackdrop(MPR.Settings["BACKDROP"])
    f:SetBackdropColor(unpack(MPR.Settings["BACKDROPCOLOR"]))
    f:SetBackdropBorderColor(MPR.Settings["BACKDROPBORDERCOLOR"].R/255, MPR.Settings["BACKDROPBORDERCOLOR"].G/255, MPR.Settings["BACKDROPBORDERCOLOR"].B/255)

    f.Title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.Title:SetPoint("TOP", 0, -12)
    f.Title:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    f.Title:SetShadowOffset(1, -1)
    f.Title:SetText("|cFF"..MPR.Colors["TITLE"].."MP Reporter|r - Reported Spells")

    local close = CreateFrame("Button", "MPR_SpellFilter_BtnClose", f, "UIPanelButtonTemplate")
    close:SetHeight(14)
    close:SetWidth(14)
    close:SetPoint("TOPRIGHT", -12, -11)
    close:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)

    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hint:SetPoint("TOPLEFT", 16, -30)
    hint:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    hint:SetTextColor(0.75, 0.75, 0.75)
    hint:SetText("Unchecked spells are not announced. Timers and Aura Info are not affected.")

    local btnAll = CreateFrame("Button", "MPR_SpellFilter_BtnAll", f, "UIPanelButtonTemplate")
    btnAll:SetHeight(16)
    btnAll:SetWidth(80)
    btnAll:SetPoint("TOPLEFT", 14, -42)
    btnAll:SetText("Select all")
    btnAll:SetScript("OnClick", function() SetRows(nil, true) end)

    local btnNone = CreateFrame("Button", "MPR_SpellFilter_BtnNone", f, "UIPanelButtonTemplate")
    btnNone:SetHeight(16)
    btnNone:SetWidth(80)
    btnNone:SetPoint("LEFT", btnAll, "RIGHT", 4, 0)
    btnNone:SetText("Select none")
    btnNone:SetScript("OnClick", function() SetRows(nil, false) end)

    local scroll = CreateFrame("ScrollFrame", "MPR_SpellFilterScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -64)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 14)

    local content = CreateFrame("Frame", "MPR_SpellFilterContent", scroll)
    content:SetWidth(360)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    local y = 0
    local n = 0
    local btnCount = 0

    local function MiniButton(label, side, enabled, x)
        btnCount = btnCount + 1
        local b = CreateFrame("Button", "MPR_SpellFilterMini"..btnCount, content, "UIPanelButtonTemplate")
        b:SetHeight(14)
        b:SetWidth(36)
        b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -(y - 1))
        b:SetText(label)
        b:SetScript("OnClick", function() SetRows(side, enabled) end)
    end

    -- Centered title line
    local function Title(text, size, hex, before, after)
        y = y + before
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        fs:SetWidth(360)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(HexToRGB(hex))
        fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
        fs:SetText(text)
        y = y + after
    end

    -- Builds one checkbox row per entry (sorted alphabetically)
    local function AddRows(entries, groupWhat, sideKey, context)
        local side = SIDES[sideKey]
        local list = {}
        for _, e in ipairs(entries) do
            local spell = e.spell or (e.key:gsub("^%u+:", ""))
            local label = e.label or spell
            local text = label
            if e.suffix then
                text = label.." |cFF"..(SUFFIX_COLORS[e.suffix] or "BEBEBE").."("..e.suffix..")|r"
            end
            table.insert(list, {
                key = e.key, spell = spell, label = label, text = text,
                sortKey = (label.." "..(e.suffix or "")):lower(),
                what = e.what or groupWhat,
            })
        end
        table.sort(list, function(a, b) return a.sortKey < b.sortKey end)

        for _, e in ipairs(list) do
            n = n + 1
            local name = "MPR_SpellFilterCB"..n
            local cb = CreateFrame("CheckButton", name, content, "UICheckButtonTemplate")
            cb:SetWidth(20)
            cb:SetHeight(20)
            cb:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
            cb:SetHitRectInsets(0, -290, 0, 0)

            -- The icon lives on its own frame so nothing can hide it
            local iconFrame = CreateFrame("Frame", nil, content)
            iconFrame:SetWidth(16)
            iconFrame:SetHeight(16)
            iconFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 28, -(y + 2))
            iconFrame:SetFrameLevel(cb:GetFrameLevel() + 1)
            local icon = iconFrame:CreateTexture(nil, "OVERLAY")
            icon:SetAllPoints(iconFrame)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetTexture(ICON_FALLBACK)

            local text = _G[name.."Text"]
            text:ClearAllPoints()
            text:SetPoint("LEFT", iconFrame, "RIGHT", 5, 0)
            text:SetWidth(225)
            text:SetJustifyH("LEFT")
            text:SetFont("Fonts\\FRIZQT__.TTF", 10)
            text:SetText(e.text)

            -- Player / Encounter tag
            local tag = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            tag:SetPoint("TOPLEFT", content, "TOPLEFT", 296, -(y + 5))
            tag:SetFont("Fonts\\FRIZQT__.TTF", 9)
            tag:SetTextColor(HexToRGB(side.color))
            tag:SetText(side.tag)

            cb.icon = icon
            cb.side = sideKey
            cb.context = context
            cb.filterKey = e.key
            cb.spellName = e.spell
            cb.labelText = e.label
            cb.what = e.what
            cb.spellId = ResolveId(e.spell)

            cb:SetScript("OnClick", function(self)
                local filter = GetFilter()
                if self:GetChecked() then
                    filter[self.filterKey] = nil
                else
                    filter[self.filterKey] = true
                end
                MPR_SpellFilter:Refresh() -- keeps duplicate rows (same key) in sync
            end)
            cb:SetScript("OnEnter", ShowTooltip)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            table.insert(Rows, cb)

            if not cb.spellId and not Wanted[e.spell] then
                Wanted[e.spell] = true
                WantedCount = WantedCount + 1
            end

            y = y + ROW_HEIGHT
        end
    end

    -- Dispels category (top of the list)
    Title("DISPELS", 13, "20B2AA", 8, 18)
    for _, d in ipairs(DispelOptions) do
        n = n + 1
        local name = "MPR_SpellFilterCB"..n
        local cb = CreateFrame("CheckButton", name, content, "UICheckButtonTemplate")
        cb:SetWidth(20)
        cb:SetHeight(20)
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
        cb:SetHitRectInsets(0, -290, 0, 0)

        local iconFrame = CreateFrame("Frame", nil, content)
        iconFrame:SetWidth(16)
        iconFrame:SetHeight(16)
        iconFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 28, -(y + 2))
        iconFrame:SetFrameLevel(cb:GetFrameLevel() + 1)
        local icon = iconFrame:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints(iconFrame)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetTexture(select(3, GetSpellInfo(d.spellId)) or ICON_FALLBACK)

        local text = _G[name.."Text"]
        text:ClearAllPoints()
        text:SetPoint("LEFT", iconFrame, "RIGHT", 5, 0)
        text:SetWidth(225)
        text:SetJustifyH("LEFT")
        text:SetFont("Fonts\\FRIZQT__.TTF", 10)
        text:SetText(d.text)

        local tag = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        tag:SetPoint("TOPLEFT", content, "TOPLEFT", 296, -(y + 5))
        tag:SetFont("Fonts\\FRIZQT__.TTF", 9)
        tag:SetTextColor(HexToRGB("20B2AA"))
        tag:SetText("Dispel")

        cb.setting = d.setting
        cb:SetScript("OnClick", function(self)
            MPR.Settings[self.setting] = self:GetChecked() and true or false
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:"..d.spellId)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(d.what, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(DispelRows, cb)

        y = y + ROW_HEIGHT
    end

    for _, section in ipairs(Catalog) do
        local side = SIDES[section.side]

        -- Section header (Player / Encounter) with its own All / None buttons
        Title(side.title, 13, side.color, 8, 18)
        MiniButton("All", section.side, true, 138)
        MiniButton("None", section.side, false, 186)
        y = y + 18

        if section.groups then
            for _, group in ipairs(section.groups) do
                Title(group.title, 10, "FFAA00", 4, 15)
                AddRows(group.entries, group.what, section.side, nil)
            end
        end

        if section.instances then
            for _, instance in ipairs(section.instances) do
                Title(instance.name, 12, "FFFFFF", 8, 17)
                for _, encounter in ipairs(instance.encounters) do
                    Title(encounter.name, 10, "FFAA00", 4, 15)
                    AddRows(encounter.entries, encounter.what, section.side, instance.name.." - "..encounter.name)
                end
            end
        end
    end
    content:SetHeight(y + 10)

    f:SetScript("OnShow", function() f:Refresh() end)
    MPR_Options:HookScript("OnHide", function() f:Hide() end)

    -- Learn IDs of spells the client couldn't resolve, straight from the combat log.
    if WantedCount > 0 then
        f:SetScript("OnEvent", function(self, event, ...)
            local _, sub, _, _, _, _, _, _, spellId, spellName = ...
            if spellName and Wanted[spellName] and type(sub) == "string" and sub:sub(1, 6) == "SPELL_" then
                MPR.Settings["SPELL_IDS"] = MPR.Settings["SPELL_IDS"] or {}
                MPR.Settings["SPELL_IDS"][spellName] = spellId
                Wanted[spellName] = nil
                WantedCount = WantedCount - 1
                if WantedCount <= 0 then self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end
                if self:IsShown() then self:Refresh() end
            end
        end)
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end
