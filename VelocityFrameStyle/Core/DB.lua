-- Velocity Frame Style: saved variables and defaults.
-- VelocityFrameStyleDB = { version, global = VFS_GlobalSettings, frames = { [VFS_FrameID] = VFS_FrameSettings },
--                          profiles = { [layoutName] = VFS_ProfileRecord } }
-- Appearance is account-wide. Only the pet-target frame's PLACEMENT is per Edit Mode layout (Core\LayoutProfile.lua).
local ADDON_NAME, VFS = ...
local Util = VFS.Util

local DB = {}
VFS.DB = DB

local DB_VERSION = 2

-- VFS_TextAnchor = "health" | "power" | "nameplate" | "above" | "below" | "hidden"
-- VFS_TextAlign  = "left" | "center" | "right"
-- VFS_ColorMode  = "stock" | "white" | "difficulty" | "class" | "reaction" | "custom"
-- VFS_TextElement = { id, label, format, anchor, align, size, color, customColor = {r,g,b} }
local function E(id, label, format, anchor, align, size, color)
  return { id = id, label = label, format = format, anchor = anchor, align = align, size = size, color = color,
    valueFormat = (id == "health" or id == "power") and "current" or nil }
end

-- Default element rows, identical for every frame (order = flow order within a slot).
local function DefaultElements()
  return {
    E("name",      "Name",     "[name]",   "nameplate", "left",   10, "stock"),
    E("level",     "Level",    "[level]",  "nameplate", "right",  10, "difficulty"),
    E("health",    "Health",   "[hp]",     "health",    "center", 10, "white"),
    E("power",     "Power",    "[power]",  "power",     "center", 10, "white"),
  }
end

-- VFS_GlobalSettings: the theme every frame inherits
DB.DEFAULT_GLOBAL = {
  barTexture = "Blizzard",        -- VFS_TextureKey (Core\Textures.lua built-ins + LibSharedMedia)
  font = "Friz Quadrata TT",      -- VFS_FontKey
  fontStyle = "OUTLINE",          -- "" | OUTLINE | THICKOUTLINE | MONOCHROME
  backingAlpha = 0.3,             -- black inner surface; opaque border alpha is independent
  -- Geometric chrome (spec \u00a7Chrome): near-black disc + rounded plate; no Blizzard frame art, no border line
  plateColor = { 0.02, 0.02, 0.02 },   -- VFS_RGB
  plateAlpha = 0.9,
  showCombatGlow = true,
  combatGlowColor = { 1, 0.1, 0.1 },   -- VFS_RGB; our replacement for Blizzard's red in-combat flash
  classColorHealth = false,       -- players only
  portraitStyle = "default",      -- default | class_old | class_new
  -- pet-target extras
  petTargetHealthOnly = true,
  petTargetFlashOnNew = true,
}

-- VFS_FrameSettings
local function DefaultFrame()
  return {
    enabled = true,
    override = {},                -- VFS_FrameOverrides: barTexture | font | fontStyle | backingAlpha | portraitStyle | plateAlpha ; nil = inherit
    elements = DefaultElements(),
  }
end

DB.FRAME_IDS = { "player", "target", "pet", "pettarget", "tot" }   -- every frame module needs a settings record

-- VFS_Placement for the pet-target frame (anchorTo = "PetFrame" is the un-moved default; LibEditMode clears it)
DB.DEFAULT_PLACEMENT = { anchorTo = "PetFrame", point = "LEFT", relPoint = "RIGHT", x = 8, y = 0 }
DB.FALLBACK_PLACEMENT = { point = "CENTER", x = 220, y = -40 }
DB.DEFAULT_PROFILE = { petTargetPlacement = DB.DEFAULT_PLACEMENT }   -- VFS_ProfileRecord

function DB.Init()
  VelocityFrameStyleDB = type(VelocityFrameStyleDB) == "table" and VelocityFrameStyleDB or {}
  local db = VelocityFrameStyleDB
  db.version = db.version or 1
  db.global = Util.ApplyDefaults(db.global or {}, DB.DEFAULT_GLOBAL)
  db.global.petTargetHideWhenSame = nil -- retired: target equality may be secret
  db.frames = type(db.frames) == "table" and db.frames or {}
  for _, id in ipairs(DB.FRAME_IDS) do
    db.frames[id] = db.frames[id] or DefaultFrame()
    db.frames[id].override = db.frames[id].override or {}
    if type(db.frames[id].elements) ~= "table" or #db.frames[id].elements == 0 then db.frames[id].elements = DefaultElements() end
    if (db.version or 1) < 2 then
      local old = {}
      for _, e in ipairs(db.frames[id].elements) do old[e.id] = e end
      local elements = DefaultElements()
      for _, e in ipairs(elements) do
        if (e.id == "name" or e.id == "level") and old[e.id] then
          for _, key in ipairs({ "anchor", "align", "size", "color", "customColor" }) do
            if old[e.id][key] ~= nil then e[key] = Util.DeepCopy(old[e.id][key]) end
          end
        end
      end
      db.frames[id].elements = elements
    end
  end
  db.version = math.max(db.version or 1, DB_VERSION)
  db.profiles = type(db.profiles) == "table" and db.profiles or {}
  -- Adopt the owner's 30% surface baseline once. Subsequent options edits persist.
  -- Only surface opacity changes; placements and text settings are untouched.
  if not db.flatBarSurfaces then
    db.global.backingAlpha = 0.3
    for _, frame in pairs(db.frames) do
      if frame.override then frame.override.backingAlpha = nil end
    end
    db.flatBarSurfaces = true
  end
  -- Removing pet-target zoom: preserve UIParent-relative anchor offsets at scale 1.
  local oldScale = db.global.petTargetScale
  if type(oldScale) == "number" and oldScale > 0 then
    for _, profile in pairs(db.profiles) do
      local p = profile.petTargetPlacement
      if p and not p.anchorTo and type(p.x) == "number" and type(p.y) == "number" then
        p.x, p.y = p.x * oldScale, p.y * oldScale
      end
    end
    db.global.petTargetScale = nil
  end
  VFS.db = db
end

function DB.Global() return VFS.db.global end
function DB.Frame(id) return VFS.db.frames[id] end
function DB.Elements(id) return VFS.db.frames[id].elements end

-- Inner fill dimensions, not whole-frame zoom. Defaults stay in Chrome.LAYOUT.
DB.DIMENSION_CONTROLS = {
  { key = "barWidth", label = "Bar width", min = 40, max = 400 },
  { key = "healthHeight", label = "Health height", min = 6, max = 80 },
  { key = "powerHeight", label = "Power height", min = 6, max = 60 },
}
function DB.BarDimension(id, key)
  local frame = DB.Frame(id)
  local value = frame and frame.dimensions and frame.dimensions[key]
  if value then return value end
  local layout = VFS.Chrome.LAYOUT[id]
  if key == "barWidth" then return layout.health.w end
  return key == "healthHeight" and layout.health.h or layout.power.h
end
function DB.SetBarDimension(id, key, value)
  local frame = DB.Frame(id)
  frame.dimensions = frame.dimensions or {}
  frame.dimensions[key] = math.floor(value + 0.5)
end

-- Effective value: the frame's override, else the theme.
function DB.Effective(id, key)
  local f = VFS.db.frames[id]
  local v = f and f.override[key]
  if v == nil then v = VFS.db.global[key] end
  return v
end

function DB.ResetFrame(id)
  VFS.db.frames[id] = DefaultFrame()
end

function DB.ResetAll()
  VFS.db.global = Util.DeepCopy(DB.DEFAULT_GLOBAL)
  for _, id in ipairs(DB.FRAME_IDS) do VFS.db.frames[id] = DefaultFrame() end
end

-- The active Edit Mode layout's record
function DB.Profile()
  local p = VFS.LayoutProfile.Current()
  -- Placement is an atomic record: nil anchorTo deliberately means UIParent.
  -- Deep-filling it restored PetFrame after every drag, immediately undoing the move.
  if type(p.petTargetPlacement) ~= "table" then
    p.petTargetPlacement = Util.DeepCopy(DB.DEFAULT_PLACEMENT)
  end
  return p
end

DB.DefaultElements = DefaultElements