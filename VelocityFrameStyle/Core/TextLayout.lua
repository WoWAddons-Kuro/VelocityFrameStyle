-- Velocity Frame Style: the text-element layout engine (spec "Text elements - the grid").
-- Lifted from VelocityPlateStyle\Skin.lua (LayoutRow / ApplyTexts) and generalised: PlateStyle has ONE bar, a unit
-- frame has several slot rectangles. The caller hands us a VFS_TextSlots table and we lay the elements out.
--
--   VFS_TextSlots = { health = Region, power = Region, nameplate = Region, above = Region, below = Region, portrait = Frame }
--     health/power/nameplate are rows laid INSIDE the region; above/below are rows hanging off the top/bottom of it.
--     portrait is the small badge on the portrait rim; elements there are centred on it.
--   VFS_TextHost  = { top = Frame (one level above the bars, owns the FontStrings), text = { [id] = FontString } }
--
-- Within a row, elements are grouped by align (left/center/right) and flow from that edge in list order with GAP px
-- between them. Overflow policy (from PlateStyle): the RIGHT group is laid first (fixed-width values), the left
-- group's last element and a single centred element are bounded on the right by the innermost right element, so a
-- long name truncates with "..." instead of running under the level. SetFont, never SetTextHeight.
local ADDON_NAME, VFS = ...
local Util, Format = VFS.Util, VFS.Format

local TextLayout = {}
VFS.TextLayout = TextLayout

local GAP = 4
local ROW_OFF = 2
local INSET = 3

-- FontStrings ----------------------------------------------------------------------------------
function TextLayout.CreateHost(parentFrame, levelAbove)
  local top = CreateFrame("Frame", nil, parentFrame)
  top:SetAllPoints(parentFrame)
  top:SetFrameLevel(parentFrame:GetFrameLevel() + (levelAbove or 3))
  return { top = top, text = {} }
end

function TextLayout.AcquireText(host, id)
  local fs = host.text[id]
  if fs then return fs end
  fs = host.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetWordWrap(false)
  host.text[id] = fs
  return fs
end

-- Apply the frame's font (family + style from theme/override) at the element's size.
function TextLayout.ApplyFont(fs, fontKey, size, style)
  fs:SetFont(Util.FontPath(fontKey), size or 10, style or "")
end

-- Colour ----------------------------------------------------------------------------------------
local function ClassColor(unit)
  if not UnitIsPlayer(unit) then return nil end
  local _, class = UnitClass(unit)
  class = Util.Plain(class)
  local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
  return c
end

local function ReactionColor(unit)
  if UnitIsPlayer(unit) and UnitIsFriend("player", unit) then return 0, 0.6, 1 end
  local r = Util.PlainNumber(UnitReaction(unit, "player"), nil)
  if not r then return 1, 1, 1 end
  if r >= 5 then return 0, 1, 0 elseif r == 4 then return 1, 1, 0 end
  return 1, 0.2, 0.2
end

-- stockFS: the stock text whose colour "stock" copies (name text for name/level, nil otherwise -> white)
function TextLayout.ColorFor(e, unit, stockFS)
  local mode = e.color
  if mode == "custom" and type(e.customColor) == "table" then
    local c = e.customColor; return c[1] or 1, c[2] or 1, c[3] or 1
  elseif mode == "difficulty" then
    local level = Util.PlainNumber(UnitLevel(unit), nil)
    if level == nil or level < 0 then return 1, 0.1, 0.1 end
    -- Our own pet (owner, Era 2026-11-26): the enemy difficulty scale is the wrong message for a pet. A pet that
    -- has fallen behind is a PROBLEM, so: yellow at the player's level or one below, red any further behind,
    -- never green or grey. Pets can't out-level the player; treat >= as "caught up" (yellow).
    if UnitIsUnit(unit, "pet") then
      local mine = Util.PlainNumber(UnitLevel("player"), nil)
      if mine and level < mine - 1 then return 1, 0.1, 0.1 end
      return 1, 0.82, 0
    end
    return VFS.Client.DifficultyColor(level)
  elseif mode == "class" then
    local c = ClassColor(unit)
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
  elseif mode == "reaction" then
    return ReactionColor(unit)
  elseif mode == "stock" then
    if stockFS then
      local ok, r, g, b = pcall(stockFS.GetTextColor, stockFS)
      if ok and r then return r, g, b end
    end
    return 1, 0.82, 0
  end
  return 1, 1, 1
end

-- Values ----------------------------------------------------------------------------------------
-- Adopted stock strings (secret-value clients): Blizzard's HealthBarText / ManaBarText are written by secure code
-- with the game's own abbreviation; their CONTENT is a secret we may never read or compare. We only re-anchor,
-- re-font and re-colour them and decide visibility from IsShown() (a widget query). PlateStyle BUG 12 pattern.
-- adopt = { health = FontString|nil, power = FontString|nil } supplied by the frame module.
function TextLayout.AdoptStock(host, id, fs)
  if not fs or host.text[id] == fs then return end
  fs.vfsAdopted = true
  fs:SetParent(host.top)
  fs:SetDrawLayer("OVERLAY")
  host.text[id] = fs
end

-- Fill every element's text + colour for `unit`. filter(e) -> bool limits the pass (health-only etc.).
-- Returns true when any element's shown-state or width changed (caller relays out).
function TextLayout.ApplyTexts(host, elements, unit, stockNameFS, filter)
  local changed = false
  for _, e in ipairs(elements) do
    if not filter or filter(e) then
      local fs = TextLayout.AcquireText(host, e.id)
      if fs.vfsAdopted then
        -- Never touch the content (secret). Blizzard hides the string when it has nothing to show.
        local visible = e.anchor ~= "hidden" and fs:IsShown()
        if fs.vfsVisible ~= visible then changed = true end
        fs.vfsVisible = visible
        fs:SetAlpha(visible and 1 or 0)          -- alpha, never Hide: Blizzard owns Show/Hide on its own string
        fs:SetTextColor(TextLayout.ColorFor(e, unit, nil))
        fs.vfsWidth = nil
        changed = true
      else
      local text
      local directValue = false
      local available = true
      if e.id == "health" or e.id == "power" then
        text, available = VFS.Client.FormatBarValue(unit, e.id, e.valueFormat or "current")
        directValue = true
      elseif Format.IsBareName(e.format) then
        text = VFS.Client.UnitDisplayName(unit)   -- may be a secret; SetText accepts it
        directValue = true
      else
        text = Format.ExpandOrEmpty(e.format, unit)
      end
      -- Direct widget values can be secret: never compare their content or measure
      -- their rendered width in Lua. Layout uses anchors instead.
      local visible = e.anchor ~= "hidden" and available and (directValue or text ~= "")
      if fs.vfsVisible ~= visible then changed = true end
      fs.vfsVisible = visible
      fs:SetText(text)
      fs:SetAlpha(1)
      fs:SetTextColor(TextLayout.ColorFor(e, unit, (e.id == "name" or e.id == "level") and stockNameFS or nil))
      fs:SetShown(visible)
      if visible and not directValue then
        local w = fs:GetStringWidth() or 0
        if fs.vfsWidth ~= w then changed = true end
        fs.vfsWidth = w
      else
        changed = true
      end
      end
    end
  end
  return changed
end

-- Sample text for Edit Mode previews
function TextLayout.ApplySample(host, elements, sample)
  for _, e in ipairs(elements) do
    local fs = TextLayout.AcquireText(host, e.id)
    local text = sample[e.id] or (e.format or ""):gsub("%[%w%%%+]+%]", "")
    if e.id == "health" or e.id == "power" then
      text = Format.SampleValue(e.id, e.valueFormat or "current")
    end
    local visible = e.anchor ~= "hidden" and text ~= ""
    fs.vfsVisible = visible
    fs:SetText(text)
    fs:SetTextColor(1, 1, 1)
    fs:SetShown(visible)
  end
end

-- Layout ----------------------------------------------------------------------------------------
local function SetP(fs, ...) PixelUtil.SetPoint(fs, ...) end

-- One horizontal row. mode = "inside" | "above" | "below"; rel = the region the row belongs to.
local function LayoutRow(items, rel, mode)
  local yOff, relV, fsV
  if mode == "above" then yOff, relV, fsV = ROW_OFF, "TOP", "BOTTOM"
  elseif mode == "below" then yOff, relV, fsV = -ROW_OFF, "BOTTOM", "TOP"
  else yOff, relV, fsV = 0, "", "" end
  local inset = mode == "inside" and INSET or 0
  local groups = { left = {}, center = {}, right = {} }
  for _, item in ipairs(items) do
    local g = groups[item.align] or groups.left
    g[#g + 1] = item.fs
  end
  -- right group
  local prev, rightInner
  for _, fs in ipairs(groups.right) do
    fs:ClearAllPoints(); fs:SetJustifyH("RIGHT"); fs:SetWidth(0)
    if prev then SetP(fs, fsV .. "RIGHT", prev, fsV .. "LEFT", -GAP, 0)
    else SetP(fs, fsV .. "RIGHT", rel, relV .. "RIGHT", -inset, yOff) end
    prev = fs; rightInner = fs
  end
  -- left group; last one bounded on the right
  prev = nil
  local n = #groups.left
  for i, fs in ipairs(groups.left) do
    fs:ClearAllPoints(); fs:SetJustifyH("LEFT"); fs:SetWidth(0)
    if prev then SetP(fs, fsV .. "LEFT", prev, fsV .. "RIGHT", GAP, 0)
    else SetP(fs, fsV .. "LEFT", rel, relV .. "LEFT", inset, yOff) end
    if i == n then
      if rightInner then SetP(fs, fsV .. "RIGHT", rightInner, fsV .. "LEFT", -GAP, 0)
      else SetP(fs, fsV .. "RIGHT", rel, relV .. "RIGHT", -inset, yOff) end
    end
    prev = fs
  end
  local leftOuter = groups.left[n]
  -- center group
  local first = groups.center[1]
  if first then
    first:ClearAllPoints(); first:SetJustifyH("CENTER"); first:SetWidth(0)
    if #groups.center == 1 and (leftOuter or rightInner) then
      if leftOuter then SetP(first, fsV .. "LEFT", leftOuter, fsV .. "RIGHT", GAP, 0)
      else SetP(first, fsV .. "LEFT", rel, relV .. "LEFT", inset, yOff) end
      if rightInner then SetP(first, fsV .. "RIGHT", rightInner, fsV .. "LEFT", -GAP, 0)
      else SetP(first, fsV .. "RIGHT", rel, relV .. "RIGHT", -inset, yOff) end
      if leftOuter then
        leftOuter:ClearAllPoints(); leftOuter:SetJustifyH("LEFT"); leftOuter:SetWidth(0)
        local before = groups.left[n - 1]
        if before then SetP(leftOuter, fsV .. "LEFT", before, fsV .. "RIGHT", GAP, 0)
        else SetP(leftOuter, fsV .. "LEFT", rel, relV .. "LEFT", inset, yOff) end
      end
    else
      SetP(first, fsV == "" and "CENTER" or fsV, rel, relV == "" and "CENTER" or relV, 0, yOff)
    end
    local rightMost, leftMost = first, first
    for i = 2, #groups.center do
      local fs = groups.center[i]
      fs:ClearAllPoints(); fs:SetWidth(0)
      if i % 2 == 0 then fs:SetJustifyH("LEFT"); SetP(fs, fsV .. "LEFT", rightMost, fsV .. "RIGHT", GAP, 0); rightMost = fs
      else fs:SetJustifyH("RIGHT"); SetP(fs, fsV .. "RIGHT", leftMost, fsV .. "LEFT", -GAP, 0); leftMost = fs end
    end
  end
end

-- Lay out every visible element into its slot. slots = VFS_TextSlots; a slot whose region is nil hides its elements.
-- 'portrait' is the badge on the portrait rim (FrameBase.PortraitBadge): elements are centred on it, align ignored,
-- and the badge itself is shown only while at least one visible element sits there.
function TextLayout.Layout(host, elements, slots)
  local rows = { health = {}, power = {}, nameplate = {}, above = {}, below = {}, portrait = {} }
  for _, e in ipairs(elements) do
    local fs = host.text[e.id]
    if fs and fs.vfsVisible then
      local list = rows[e.anchor]
      if list and slots[e.anchor] then list[#list + 1] = { fs = fs, align = e.align }
      else fs:Hide() end
    end
  end
  if slots.health then LayoutRow(rows.health, slots.health, "inside") end
  if slots.power then LayoutRow(rows.power, slots.power, "inside") end
  if slots.nameplate then LayoutRow(rows.nameplate, slots.nameplate, "inside") end
  if slots.above then LayoutRow(rows.above, slots.above, "above") end
  if slots.below then LayoutRow(rows.below, slots.below, "below") end
  local badge = slots.portrait
  if badge then
    for _, item in ipairs(rows.portrait) do
      item.fs:ClearAllPoints(); item.fs:SetJustifyH("CENTER"); item.fs:SetWidth(0)
      SetP(item.fs, "CENTER", badge, "CENTER", 0, 0)
    end
    if badge.SetShown then badge:SetShown(#rows.portrait > 0) end
  end
end

-- Hide strings for elements that no longer exist in the list
function TextLayout.PruneTexts(host, elements)
  local live = {}
  for _, e in ipairs(elements) do live[e.id] = true end
  for id, fs in pairs(host.text) do if not live[id] then fs:Hide(); fs:SetText("") end end
end