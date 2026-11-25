-- Velocity Frame Style: the PlayerFrame module. Slots: health bar, power bar, and 'nameplate' = the strip where
-- Blizzard's name sits (we use the health bar's top edge as that row's anchor region on frames without a strip).
local ADDON_NAME, VFS = ...
local Client, DB, FrameBase = VFS.Client, VFS.DB, VFS.FrameBase

local Player = {}
VFS.Player = Player

-- Era: fill the art slot (EasyFrames-Era numbers: health 27 px at TOPLEFT 90,-27). Forever: MovableBars is empty
-- so Geometry skips. Measured constants per flavour live here, not in Client (they are policy, not API).
local ERA_HEALTH = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 90, y = -27, width = 119, height = 27 }

function Player.Create()
  local st = FrameBase.Acquire("player")
  if not st then return end
  local hb, pb = st.bars.health and st.bars.health.draw, st.bars.power and st.bars.power.draw
  -- The name row sits above the health bar; Player has no reaction strip
  st.slots = { health = hb, power = pb, nameplate = hb and FrameBase.NameRowAbove(st, hb), above = hb, below = pb or hb }
  if st.bars.health and st.bars.health.inPlace then
    VFS.Geometry.PlaceBar("player", st.bars.health.stock, { point = ERA_HEALTH.point, relTo = st.button, relPoint = ERA_HEALTH.relPoint, x = ERA_HEALTH.x, y = ERA_HEALTH.y, height = ERA_HEALTH.height })
  end
  FrameBase.HookCommon(st)
  -- Blizzard re-applies art/status on these
  if PlayerFrame_ToPlayerArt then hooksecurefunc("PlayerFrame_ToPlayerArt", function() FrameBase.Restyle("player") end) end
  if PlayerFrame_UpdateArt then hooksecurefunc("PlayerFrame_UpdateArt", function() FrameBase.Restyle("player") end) end
  FrameBase.Restyle("player")
  return st
end

function Player.OnEvent(event, unit)
  if event == "UNIT_LEVEL" or event == "PLAYER_LEVEL_UP" or event == "UNIT_NAME_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    FrameBase.ApplyTexts(VFS.Frames.player)
  end
end