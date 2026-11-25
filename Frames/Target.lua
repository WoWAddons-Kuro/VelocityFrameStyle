-- Velocity Frame Style: the TargetFrame module. Slots: health, power, and 'nameplate' = Blizzard's reaction-coloured
-- strip (TargetFrameNameBackground on Era, TargetFrameContentMain.ReputationColor on Forever) where the name and level sit.
local ADDON_NAME, VFS = ...
local Client, DB, FrameBase = VFS.Client, VFS.DB, VFS.FrameBase

local Target = {}
VFS.Target = Target

local ERA_HEALTH = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -90, y = -27, height = 27 }

function Target.Create()
  local st = FrameBase.Acquire("target")
  if not st then return end
  local hb, pb = st.bars.health and st.bars.health.draw, st.bars.power and st.bars.power.draw
  local strip = Client.NameBackground("target")
  st.slots = { health = hb, power = pb, nameplate = strip or (hb and FrameBase.NameRowAbove(st, hb)), above = hb, below = pb or hb }
  if st.bars.health and st.bars.health.inPlace then
    VFS.Geometry.PlaceBar("target", st.bars.health.stock, { point = ERA_HEALTH.point, relTo = st.button, relPoint = ERA_HEALTH.relPoint, x = ERA_HEALTH.x, y = ERA_HEALTH.y, height = ERA_HEALTH.height })
  end
  FrameBase.HookCommon(st)
  -- Classification changes swap the art; name/level/colours refresh with the unit
  if TargetFrame.CheckClassification then hooksecurefunc(TargetFrame, "CheckClassification", function() FrameBase.Restyle("target") end) end
  if TargetFrame_CheckClassification then hooksecurefunc("TargetFrame_CheckClassification", function() FrameBase.Restyle("target") end) end
  FrameBase.Restyle("target")
  return st
end

function Target.OnEvent(event, unit)
  local st = VFS.Frames.target
  if not st then return end
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    FrameBase.Restyle("target")
  elseif (event == "UNIT_LEVEL" or event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" or event == "UNIT_NAME_UPDATE") and unit == "target" then
    FrameBase.ApplyTexts(st)
  end
end