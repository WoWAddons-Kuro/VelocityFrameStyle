-- Velocity Frame Style: saved variables and defaults.
-- VelocityFrameStyleDB = { version, global = VFS_GlobalSettings, frames = { [VFS_FrameID] = VFS_FrameSettings },
--                          profiles = { [layoutName] = VFS_ProfileRecord } }
-- Appearance is account-wide. Only the pet-target frame's PLACEMENT is per Edit Mode layout (Core\LayoutProfile.lua).
local ADDON_NAME, VFS = ...
local Util = VFS.Util

local DB = {}
VFS.DB = DB

local DB_VERSION = 1

-- VFS_TextAnchor = "health" | "power" | "nameplate" | "above" | "below" | "hidden"
-- VFS_TextAlign  = "left" | "center" | "right"
-- VFS_ColorMode  = "stock" | "white" | "difficulty" | "class" | "reaction" | "custom"
-- VFS_TextElement = { id, label, format, anchor, align, size, color, customColor = {r,g,b} }
local function E(id, label, format, anchor, align, size, color)
  return { id = id, label = label, format = format, anchor = anchor, align = align, size = size, color = color }
end

-- Default element rows, identical for every frame (order = flow order within a slot).
local function DefaultElements()
  return {
    E("name",      "Name",     "[name]",   "nameplate", "center", 10, "stock"),
    E("level",     "Level",    "[level]",  "nameplate", "right",  10, "difficulty"),
    E("health",    "Health",   "[hp]",     "health",    "center", 10, "white"),
    E("healthpct", "Health %", "[hp%]",    "hidden",    "right",  10, "white"),
    E("power",     "Power",    "[power]",  "power",     "center", 10, "white"),
    E("powerpct",  "Power %",  "[power%]", "hidden",    "right",  10, "white"),
  }
end

-- VFS_GlobalSettings: the theme every frame inherits
DB.DEFAULT_GLOBAL = {
  barTexture = "Blizzard",        -- VFS_TextureKey (Core\Textures.lua built-ins + LibSharedMedia)
  font = "Friz Quadrata TT",      -- VFS_FontKey
  fontStyle = "OUTLINE",          -- "" | OUTLINE | THICKOUTLINE | MONOCHROME
  backingAlpha = 0.6,             -- black backdrop behind every bar
  -- Geometric chrome (spec \u00a7Chrome): near-black disc + rounded plate; no Blizzard frame art, no border line
  plateColor = { 0.02, 0.02, 0.02 },   -- VFS_RGB
  plateAlpha = 0.9,
  showCombatGlow = true,
  combatGlowColor = { 1, 0.1, 0.1 },   -- VFS_RGB; our replacement for Blizzard's red in-combat flash
  classColorHealth = false,       -- players only
  portraitStyle = "default",      -- default | class_old | class_new
  -- pet-target extras
  petTargetHideWhenSame = false,
  petTargetFlashOnNew = true,
  petTargetScale = 0.8,
}

-- VFS_FrameSettings
local function DefaultFrame()
  return {
    enabled = true,
    override = {},                -- VFS_FrameOverrides: barTexture | font | fontStyle | backingAlpha | portraitStyle | plateAlpha ; nil = inherit
    elements = DefaultElements(),
  }
end

DB.FRAME_IDS = { "player", "target", "pet", "pettarget" }   -- VFS_FrameID, M0 set

-- VFS_Placement for the pet-target frame (anchorTo = "PetFrame" is the un-moved default; LibEditMode clears it)
DB.DEFAULT_PLACEMENT = { anchorTo = "PetFrame", point = "LEFT", relPoint = "RIGHT", x = 8, y = 0 }
DB.FALLBACK_PLACEMENT = { point = "CENTER", x = 220, y = -40 }
DB.DEFAULT_PROFILE = { petTargetPlacement = DB.DEFAULT_PLACEMENT }   -- VFS_ProfileRecord

function DB.Init()
  VelocityFrameStyleDB = type(VelocityFrameStyleDB) == "table" and VelocityFrameStyleDB or {}
  local db = VelocityFrameStyleDB
  db.version = db.version or DB_VERSION
  db.global = Util.ApplyDefaults(db.global or {}, DB.DEFAULT_GLOBAL)
  db.frames = type(db.frames) == "table" and db.frames or {}
  for _, id in ipairs(DB.FRAME_IDS) do
    db.frames[id] = db.frames[id] or DefaultFrame()
    db.frames[id].override = db.frames[id].override or {}
    if type(db.frames[id].elements) ~= "table" or #db.frames[id].elements == 0 then db.frames[id].elements = DefaultElements() end
  end
  db.profiles = type(db.profiles) == "table" and db.profiles or {}
  VFS.db = db
end

function DB.Global() return VFS.db.global end
function DB.Frame(id) return VFS.db.frames[id] end
function DB.Elements(id) return VFS.db.frames[id].elements end

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
  Util.ApplyDefaults(p, DB.DEFAULT_PROFILE)
  return p
end

DB.DefaultElements = DefaultElements