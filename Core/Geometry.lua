-- Velocity Frame Style: the ONE audited exception to R2 (never move a Blizzard region).
-- Era's stock bars are plain, unmasked StatusBar children that EasyFrames-Era resizes/re-anchors safely; the slot
-- in the frame art is bigger than Blizzard's bar, so filling it needs SetHeight/SetPoint on the stock bar. Only bars
-- listed by Client.MovableBars(frameID) may be touched, only out of combat, only through this file; a blocked call
-- is reported once (Util.WarnOnce) and never retried in combat. On Forever MovableBars() is empty: nothing happens.
local ADDON_NAME, VFS = ...
local Util = VFS.Util

local Geometry = {}
VFS.Geometry = Geometry

local function Allowed(frameID, bar)
  local movable = VFS.Client.MovableBars(frameID)
  return movable and movable[bar] == true
end

-- Re-anchor + resize a stock bar. Returns true when applied, false when skipped (not allowed / in combat).
-- spec = { point, relTo, relPoint, x, y, width, height }
function Geometry.PlaceBar(frameID, bar, spec)
  if not bar or not Allowed(frameID, bar) then return false end
  if InCombatLockdown() then return false end
  local ok, err = pcall(function()
    bar:ClearAllPoints()
    bar:SetPoint(spec.point, spec.relTo, spec.relPoint, spec.x or 0, spec.y or 0)
    if spec.width then bar:SetWidth(spec.width) end
    if spec.height then bar:SetHeight(spec.height) end
  end)
  if not ok then Util.WarnOnce("geometry:" .. frameID, "could not place a bar on " .. frameID .. ": " .. tostring(err)) end
  -- Blizzard re-anchors some bars in its own art functions; re-assert once after it does.
  if ok and not bar.vfsGeometryHooked then
    bar.vfsGeometryHooked = true
    bar.vfsGeometrySpec = spec
    hooksecurefunc(bar, "SetPoint", function(b, _, _, _, _, _, flag)
      if flag == "VFS" or InCombatLockdown() or not b.vfsGeometrySpec then return end
      local s = b.vfsGeometrySpec
      b:ClearAllPoints()
      b:SetPoint(s.point, s.relTo, s.relPoint, s.x or 0, s.y or 0, "VFS")
    end)
  elseif ok then
    bar.vfsGeometrySpec = spec
  end
  return ok
end