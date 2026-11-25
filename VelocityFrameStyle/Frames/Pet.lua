-- Velocity Frame Style: the PetFrame module. Blizzard's pet frame has no level region on either client, so the
-- 'level' grid element is the only pet level. Stock bars styled in place and sized to the fixed M0 layout
-- (EF-Forever: health 70x10, power 76x7, both hung off the portrait's right edge).
local ADDON_NAME, VFS = ...
local Client, DB, FrameBase, Chrome, Geometry = VFS.Client, VFS.DB, VFS.FrameBase, VFS.Chrome, VFS.Geometry

local Pet = {}
VFS.Pet = Pet

local function PlaceBars(st)
  local L = Chrome.LAYOUT.pet
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  local portrait = Client.Portrait("pet")
  if hb and portrait then Geometry.PlaceBar("pet", hb, { point = "BOTTOMLEFT", relTo = portrait, relPoint = "RIGHT", x = 2, y = -3.5, width = L.health.w, height = L.health.h }) end
  if pb and hb then Geometry.PlaceBar("pet", pb, { point = "TOPLEFT", relTo = hb, relPoint = "BOTTOMLEFT", x = 0, y = -1, width = L.health.w, height = L.power.h }) end
end

function Pet.Create()
  local st = FrameBase.Acquire("pet")
  if not st then return end
  PlaceBars(st)
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  st.slots = { health = hb, power = pb, nameplate = hb and FrameBase.NameRowAbove(st, hb, 11, 1), above = hb, below = pb or hb }
  FrameBase.HookCommon(st)
  if PetFrame.Update then hooksecurefunc(PetFrame, "Update", function() PlaceBars(st); FrameBase.Restyle("pet") end) end
  if PetFrame_Update then hooksecurefunc("PetFrame_Update", function() PlaceBars(st); FrameBase.Restyle("pet") end) end
  FrameBase.Restyle("pet")
  return st
end

function Pet.OnEvent(event, unit)
  local st = VFS.Frames.pet
  if not st then return end
  if event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
    PlaceBars(st); FrameBase.Restyle("pet"); FrameBase.OnCombatChanged(st)
  elseif event == "UNIT_FLAGS" and unit == "pet" then
    FrameBase.OnCombatChanged(st)
  elseif (event == "UNIT_LEVEL" or event == "UNIT_NAME_UPDATE") and unit == "pet" then
    FrameBase.ApplyTexts(st)
  end
end