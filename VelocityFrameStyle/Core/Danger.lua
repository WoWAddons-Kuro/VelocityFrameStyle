-- Velocity Frame Style: Target danger cues (SPECS/13_Target_Danger_Cues.md). Pure decisions, no drawing.
-- Copied from VelocityPlateStyle Core.lua / Skin.lua (workspace rule: copy, never a cross-addon dependency).
--
-- VFS_DangerSettings = DB.Danger() = { overLevelMode, overLevelThreshold, skullAtLevelsAbove, reactionHealth }
-- Every unit read goes through Util.Plain / Util.PlainNumber (R8): a secret level means "no cue this pass";
-- a secret attackable flag counts as hostile (hostiles are the secret ones on Forever).
local ADDON_NAME, VFS = ...
local Util = VFS.Util

local Danger = {}
VFS.Danger = Danger

Danger.SKULL_GAME_LEVELS = 10            -- the game itself reports -1 ("??") about this far above the player
Danger.RED    = { 1, 0.15, 0.1 }         -- skull red: danger row, red Level, red ring, red sweep
Danger.YELLOW = { 1, 0.85, 0.1 }         -- contrast sweep over a red bar
Danger.OVER_LEVEL_MODES = { "none", "animated", "red", "animatedRed" }   -- VFS_OverLevelMode

local function Settings() return VFS.DB.Danger() end

-- Over-level cues are for things that can hurt you. A friendly / non-attackable unit never gets them.
function Danger.IsHostileThreat(unit)
  return Util.Plain(UnitCanAttack("player", unit)) ~= false
end

-- VFS_SkullCount: -1 = "??" (replace the number), 0 = none, N = N skull glyphs before the number.
-- `level` must already be Plain()-ed (nil = unknown/secret -> 0).
function Danger.SkullCount(level, unit)
  if level == nil then return 0 end
  if level < 0 then return -1 end
  if unit and not Danger.IsHostileThreat(unit) then return 0 end
  local diff = level - (Util.PlainNumber(UnitLevel("player"), nil) or 1)
  if diff > Danger.SKULL_GAME_LEVELS then return -1 end
  local at = Settings().skullAtLevelsAbove or Danger.SKULL_GAME_LEVELS
  if diff < at then return 0 end
  return diff
end

-- unitLevel >= playerLevel + threshold, or the game's own skull. Friendlies never.
function Danger.IsOverLevel(unit)
  if not Danger.IsHostileThreat(unit) then return false end
  local level = Util.PlainNumber(UnitLevel(unit), nil)
  if level == nil then return false end
  if level < 0 then return true end
  local mine = Util.PlainNumber(UnitLevel("player"), nil) or 1
  return level >= mine + (Settings().overLevelThreshold or 2)
end

-- Anything that should read skull-red: over the threshold, or any skull form.
function Danger.IsDangerous(unit)
  if Danger.IsOverLevel(unit) then return true end
  return Danger.SkullCount(Util.PlainNumber(UnitLevel(unit), nil), unit) ~= 0
end

-- Text of the danger row above the name: "" (hide) | "??" | skull glyphs .. level.
function Danger.RowText(unit)
  local level = Util.PlainNumber(UnitLevel(unit), nil)
  local n = Danger.SkullCount(level, unit)
  if n < 0 then return VFS.Format.SKULL_TEXT end
  if n > 0 then return string.rep(VFS.Format.SKULL_ICON, n) .. tostring(level) end
  return ""
end

-- Health-bar reaction colour for the `reactionHealth` option (NPCs only; players -> nil = caller's class/green rule).
-- UnitReaction: 1..3 hostile, 4 neutral, 5..8 friendly. A secret reaction -> nil (never compared).
-- An attacked neutral keeps reaction 4 but is fighting you: it reads HOSTILE red while in combat (owner 2026-11-27:
-- "attacked neutral stayed yellow"). The combat test is THE SAME ONE the combat glow uses (Chrome.UpdateCombat:
-- UnitAffectingCombat(unit) == true), so the red bar and the aggro glow always agree - including on Forever, where
-- that call is what already lights the glow on aggressive targets.
function Danger.ReactionColor(unit)
  if Util.Plain(UnitIsPlayer(unit)) == true then return nil end
  local r = Util.PlainNumber(UnitReaction(unit, "player"), nil)
  if r == nil then return nil end
  if r <= 3 then return 1, 0.2, 0.2 end
  if r == 4 then
    if UnitAffectingCombat(unit) == true and Danger.IsHostileThreat(unit) then return 1, 0.2, 0.2 end
    return 1, 1, 0
  end
  return 0, 1, 0
end