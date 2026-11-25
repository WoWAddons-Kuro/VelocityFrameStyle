-- Velocity Frame Style: the PetFrame module. Blizzard's pet frame has NO level region on either client, so the
-- 'level' grid element is the only pet level there is (what VelocityPetTargetFrame's badge did). Slots: health, power,
-- nameplate = a name row above the health bar (the pet art has no reaction strip).
--
-- Era geometry: EasyFrames-Era leaves the stock 13 px bar inside a ~17 px art slot (the dark ring the owner saw);
-- we fill the slot: health 17 px, power 8 px, flush, inside UI-SmallTargetingFrame's cut-out. Tuned in game.
local ADDON_NAME, VFS = ...
local Client, DB, FrameBase = VFS.Client, VFS.DB, VFS.FrameBase

local Pet = {}
VFS.Pet = Pet

local ERA_HEALTH = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 45, y = -20, width = 73, height = 17 }
local ERA_POWER  = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -1, width = 73, height = 8 }   -- relTo = health bar

function Pet.Create()
  local st = FrameBase.Acquire("pet")
  if not st then return end
  local hb, pb = st.bars.health and st.bars.health.draw, st.bars.power and st.bars.power.draw
  st.slots = { health = hb, power = pb, nameplate = hb and FrameBase.NameRowAbove(st, hb, 12, 1), above = hb, below = pb or hb }
  if st.bars.health and st.bars.health.inPlace then
    VFS.Geometry.PlaceBar("pet", st.bars.health.stock, { point = ERA_HEALTH.point, relTo = st.button, relPoint = ERA_HEALTH.relPoint, x = ERA_HEALTH.x, y = ERA_HEALTH.y, width = ERA_HEALTH.width, height = ERA_HEALTH.height })
    if st.bars.power and st.bars.power.inPlace then
      VFS.Geometry.PlaceBar("pet", st.bars.power.stock, { point = ERA_POWER.point, relTo = st.bars.health.stock, relPoint = ERA_POWER.relPoint, x = ERA_POWER.x, y = ERA_POWER.y, width = ERA_POWER.width, height = ERA_POWER.height })
    end
  end
  FrameBase.HookCommon(st)
  if PetFrame.Update then hooksecurefunc(PetFrame, "Update", function() FrameBase.Restyle("pet") end) end
  if PetFrame_Update then hooksecurefunc("PetFrame_Update", function() FrameBase.Restyle("pet") end) end
  FrameBase.Restyle("pet")
  return st
end

function Pet.OnEvent(event, unit)
  local st = VFS.Frames.pet
  if not st then return end
  if event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
    FrameBase.Restyle("pet")
  elseif (event == "UNIT_LEVEL" or event == "UNIT_NAME_UPDATE") and unit == "pet" then
    FrameBase.ApplyTexts(st)
  end
end