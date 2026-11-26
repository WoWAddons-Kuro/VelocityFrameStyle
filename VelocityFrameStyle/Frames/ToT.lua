-- Velocity Frame Style: the Target-of-Target module (TargetFrameToT). Small-frame treatment like Pet: stock bars
-- styled in place and sized to Chrome.LAYOUT.tot, portrait left, bars right. Blizzard's ToT chrome is alpha-zeroed.
-- Pulled forward from M3 because the frame is already on screen next to the restyled Target (owner 2026-11-25).
local ADDON_NAME, VFS = ...
local Client, DB, FrameBase, Chrome, Geometry = VFS.Client, VFS.DB, VFS.FrameBase, VFS.Chrome, VFS.Geometry

local ToT = {}
VFS.ToT = ToT

local function PlaceBars(st)
  local L = Chrome.LAYOUT.tot
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  local portrait = Client.Portrait("tot")
  if hb and portrait then Geometry.PlaceBar("tot", hb, { point = "BOTTOMLEFT", relTo = portrait, relPoint = "RIGHT", x = 2, y = -3.5, width = L.health.w, height = L.health.h }) end
  if pb and hb then Geometry.PlaceBar("tot", pb, { point = "TOPLEFT", relTo = hb, relPoint = "BOTTOMLEFT", x = 0, y = -FrameBase.BAR_BORDER_WIDTH, width = L.power.w, height = L.power.h }) end
end

function ToT.Create()
  if not Client.UnitButton("tot") then return end
  local st = FrameBase.Acquire("tot")
  if not st then return end
  PlaceBars(st)
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  st.slots = { health = hb, power = pb, nameplate = hb and FrameBase.NameRowAbove(st, hb, 11, 1), above = hb, below = pb or hb, portrait = st.portraitBadge }
  FrameBase.HookCommon(st)
  -- Blizzard refreshes ToT from the target frame's update; re-assert after it
  if TargetFrame.UpdateTargetOfTarget then hooksecurefunc(TargetFrame, "UpdateTargetOfTarget", function() PlaceBars(st); FrameBase.Restyle("tot") end) end
  if TargetFrameToT and TargetFrameToT.Update then hooksecurefunc(TargetFrameToT, "Update", function() PlaceBars(st); FrameBase.Restyle("tot") end) end
  FrameBase.Restyle("tot")
  return st
end

function ToT.OnEvent(event, unit)
  local st = VFS.Frames.tot
  if not st then return end
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" or (event == "UNIT_TARGET" and unit == "target") then
    PlaceBars(st); FrameBase.Restyle("tot"); FrameBase.OnCombatChanged(st)
  end
end