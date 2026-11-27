-- Velocity Frame Style: the PlayerFrame module. Stock bars styled in place; Geometry sizes them to the fixed M0
-- layout (EasyFrames-Forever constants: health 113x24, power 117x12) when the client lets us move them.
local ADDON_NAME, VFS = ...
local Client, DB, FrameBase, Chrome, Geometry = VFS.Client, VFS.DB, VFS.FrameBase, VFS.Chrome, VFS.Geometry

local Player = {}
VFS.Player = Player

local function PlaceBars(st)
  local L = Chrome.LAYOUT.player
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  -- EF-Forever puts the health bar CENTERed in the frame at (-30, 8) mirrored for the player (bars right of portrait)
  if hb then Geometry.PlaceBar("player", hb, { point = "LEFT", relTo = st.button, relPoint = "LEFT", x = 86, y = 6, width = L.health.w, height = L.health.h }) end
  if pb and hb then Geometry.PlaceBar("player", pb, { point = "TOPLEFT", relTo = hb, relPoint = "BOTTOMLEFT", x = 0, y = -FrameBase.BAR_BORDER_WIDTH, width = L.power.w, height = L.power.h }) end
end

function Player.Create()
  local st = FrameBase.Acquire("player")
  if not st then return end
  PlaceBars(st)
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  st.slots = { health = hb, power = pb, nameplate = hb and FrameBase.NameRowAbove(st, hb), above = hb, below = pb or hb, portrait = st.portraitBadge }
  FrameBase.HookCommon(st)
  -- Blizzard re-applies art and bar geometry here; re-assert ours after it
  for _, fn in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_UpdateArt", "PlayerFrame_UpdateHealthBarVisuals", "PlayerFrame_UpdateManaBarVisuals" }) do
    if _G[fn] then hooksecurefunc(fn, function() PlaceBars(st); FrameBase.Restyle("player") end) end
  end
  -- The stock level text comes back after Blizzard's own level refresh on BOTH clients, by different routes:
  --   Forever: PlayerFrame_UpdateLevel resets text alpha to 1 without calling SetAlpha (verified in game).
  --   Era:     PlayerFrame_Update (UNIT_LEVEL / PLAYER_ENTERING_WORLD / ToPlayerArt) does
  --            PlayerLevelText:SetVertexColor(r, g, b, 1.0) - a vertex-alpha write our SetAlpha hook never sees
  --            (owner 2026-11-27: "12" under the badge on Era). Re-suppress after either. Visibility untouched.
  local function ResuppressLevel()
    if not DB.Frame("player").enabled then return end
    for _, region in ipairs(Client.StockLevelRegions("player")) do
      FrameBase.SetChromeSuppressed(region, "player", true)
    end
  end
  for _, fn in ipairs({ "PlayerFrame_UpdateLevel", "PlayerFrame_Update" }) do
    if _G[fn] then hooksecurefunc(fn, ResuppressLevel) end
  end
  FrameBase.Restyle("player")
  return st
end

function Player.OnEvent(event, unit)
  local st = VFS.Frames.player
  if not st then return end
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then FrameBase.OnCombatChanged(st) end
  if event == "UNIT_LEVEL" or event == "PLAYER_LEVEL_UP" or event == "UNIT_NAME_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    FrameBase.ApplyTexts(st)
  end
end