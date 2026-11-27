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
  -- Bars WE created (bar.vfsOwned: the druid mana bar, SPECS/14) are always ours to place; the MovableBars
  -- audit is for Blizzard's stock regions only.
  if bar and bar.vfsOwned then return true end
  local movable = VFS.Client.MovableBars(frameID)
  return movable and movable[bar] == true
end

-- Re-anchor + resize a stock bar. Returns true when applied, false when skipped (not allowed / in combat).
-- spec = { point, relTo, relPoint, x, y, width, height }
function Geometry.PlaceBar(frameID, bar, spec)
  if not bar or not Allowed(frameID, bar) then return false end
  if InCombatLockdown() then return false end
  if VFS.DB.Frame(frameID) then
    spec.width = VFS.DB.BarDimension(frameID, "barWidth")
    -- Stock bars take the user's dimension sliders; an owned extra bar (mana) keeps the height its module asked for.
    if not bar.vfsOwned then
      local kind = bar == VFS.Client.HealthBar(frameID) and "healthHeight" or "powerHeight"
      spec.height = VFS.DB.BarDimension(frameID, kind)
    end
  end
  local ok, err = pcall(function()
    bar:ClearAllPoints()
    bar:SetPoint(spec.point, spec.relTo, spec.relPoint, spec.x or 0, spec.y or 0)
    if spec.width then bar:SetWidth(spec.width) end
    if spec.height then bar:SetHeight(spec.height) end
  end)
  if not ok then Util.WarnOnce("geometry:" .. frameID, "could not place a bar on " .. frameID .. ": " .. tostring(err)) end
  -- Blizzard re-anchors AND re-sizes bars in its own art functions; re-assert after either. Size matters as much as
  -- position: on Forever, shifting into Bear changes max health, which re-runs PlayerFrame_UpdateHealthBarVisuals ->
  -- healthBarContainer/HealthBar:SetWidth(124) with NO SetPoint, so a point-only hook let the health bar grow to 124
  -- while power/mana stayed 113 (owner 2026-11-27: "bars get short on Bear and stay that way until /reload").
  if ok and not bar.vfsGeometryHooked then
    bar.vfsGeometryHooked = true
    bar.vfsGeometrySpec = spec
    local reasserting = false
    local function Reassert(b)
      if reasserting or InCombatLockdown() or not b.vfsGeometrySpec then return end
      reasserting = true
      local s = b.vfsGeometrySpec
      b:ClearAllPoints()
      b:SetPoint(s.point, s.relTo, s.relPoint, s.x or 0, s.y or 0, "VFS")
      if s.width then b:SetWidth(s.width) end
      if s.height then b:SetHeight(s.height) end
      reasserting = false
    end
    hooksecurefunc(bar, "SetPoint", function(b, _, _, _, _, _, flag)
      if flag ~= "VFS" then Reassert(b) end
    end)
    hooksecurefunc(bar, "SetWidth", Reassert)
    hooksecurefunc(bar, "SetHeight", Reassert)
    hooksecurefunc(bar, "SetSize", Reassert)
  elseif ok then
    bar.vfsGeometrySpec = spec
  end
  return ok
end

-- Resize inner surfaces only; border/background/text anchors follow automatically.
function Geometry.ApplyBarDimensions(st)
  if InCombatLockdown() then st.dimensionsPending = true; return false end
  st.dimensionsPending = nil
  -- Owned frames (pettarget, tot - Frames\OwnedUnitFrame.lua): the bars are ours, always resizable.
  local owned = VFS.OwnedUnitFrame and VFS.OwnedUnitFrame.Get(st.id)
  local width = VFS.DB.BarDimension(st.id, "barWidth")
  local healthH, powerH = VFS.DB.BarDimension(st.id, "healthHeight"), VFS.DB.BarDimension(st.id, "powerHeight")
  for kind, bar in pairs(st.bars) do
    if (owned or Allowed(st.id, bar.stock)) and not bar.stock.vfsOwned then   -- owned extra bars keep their own height
      local height = kind == "health" and healthH or powerH
      bar.stock:SetWidth(width)
      bar.stock:SetHeight(height)
      if bar.stock.vfsGeometrySpec then
        bar.stock.vfsGeometrySpec.width = width
        bar.stock.vfsGeometrySpec.height = height
      end
    end
  end
  -- Small owned frame: the button rect (= the Edit Mode selection box) follows the bars.
  if owned and owned.spec.small then VFS.OwnedUnitFrame.FitSmall(owned, width, healthH, powerH) end
  return true
end