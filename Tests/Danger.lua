-- Run from repository root: lua5.1 Tests/Danger.lua   (SPECS/13_Target_Danger_Cues.md)
local ns = {}
local function load(path) assert(loadfile('VelocityFrameStyle/' .. path))('VelocityFrameStyle', ns) end
load('Core/Util.lua'); load('Core/Format.lua'); load('Core/Danger.lua')

-- Fake secret (Forever): any inspection errors; only issecretvalue may look at it.
local secretMeta = {}
local function secret(v) return setmetatable({ value = v }, secretMeta) end
local function forbidden() error('secret inspected') end
secretMeta.__lt, secretMeta.__le, secretMeta.__eq, secretMeta.__add, secretMeta.__sub, secretMeta.__tostring = forbidden, forbidden, forbidden, forbidden, forbidden, forbidden
function issecretvalue(v) return type(v) == 'table' and getmetatable(v) == secretMeta end

-- Unit stubs
local units = {}
function UnitLevel(u) return units[u].level end
function UnitCanAttack(_, u) return units[u].attackable end
function UnitReaction(u) return units[u].reaction end
function UnitIsPlayer(u) return units[u].player == true end

local danger = { overLevelMode = 'animatedRed', overLevelThreshold = 2, skullAtLevelsAbove = 10, reactionHealth = false }
ns.DB = { Danger = function() return danger end }
local D = ns.Danger

local function mob(level, attackable, reaction, player) units.target = { level = level, attackable = attackable ~= false, reaction = reaction or 2, player = player } end
units.player = { level = 10 }

-- SkullCount
mob(-1);  assert(D.SkullCount(-1, 'target') == -1, 'game skull => ??')
mob(21);  assert(D.SkullCount(21, 'target') == -1, 'diff 11 > game levels => ??')
danger.skullAtLevelsAbove = 3
mob(13);  assert(D.SkullCount(13, 'target') == 3, 'diff 3 at skullAt 3 => 3 glyphs')
mob(12);  assert(D.SkullCount(12, 'target') == 0, 'diff 2 below skullAt 3 => none')
mob(15, false); assert(D.SkullCount(15, 'target') == 0, 'friendly => none')
assert(D.SkullCount(nil, 'target') == 0, 'unknown level => none')
danger.skullAtLevelsAbove = 10

-- IsOverLevel (threshold 2, player 10)
mob(12); assert(D.IsOverLevel('target') == true,  '12 vs 10 +2 => over')
mob(11); assert(D.IsOverLevel('target') == false, '11 => not over')
mob(-1); assert(D.IsOverLevel('target') == true,  'skull => over')
mob(12, false); assert(D.IsOverLevel('target') == false, 'friendly => never')
mob(secret(30)); assert(D.IsOverLevel('target') == false, 'secret level => no cue')
units.target = { level = 30, attackable = secret(true) }; assert(D.IsOverLevel('target') == true, 'secret attackable counts as hostile')

-- IsDangerous: skull count alone lights it
danger.overLevelThreshold = 5; danger.skullAtLevelsAbove = 3
mob(13); assert(D.IsDangerous('target') == true, '3 skulls but under +5 threshold => still dangerous')
mob(12); assert(D.IsDangerous('target') == false)
danger.overLevelThreshold = 2; danger.skullAtLevelsAbove = 10

-- RowText
mob(11); assert(D.RowText('target') == '', 'no skulls => hide row')
mob(-1); assert(D.RowText('target') == '??')
danger.skullAtLevelsAbove = 2
mob(12); assert(D.RowText('target') == ns.Format.SKULL_ICON .. ns.Format.SKULL_ICON .. '12', 'two glyphs then the level')
danger.skullAtLevelsAbove = 10

-- ReactionColor
local function rgb(...) return { ... } end
mob(10, true, 2); local c = rgb(D.ReactionColor('target')); assert(c[1] == 1 and c[2] == 0.2, 'hostile red')
mob(10, true, 4); c = rgb(D.ReactionColor('target')); assert(c[1] == 1 and c[2] == 1 and c[3] == 0, 'neutral yellow')
mob(10, true, 5); c = rgb(D.ReactionColor('target')); assert(c[1] == 0 and c[2] == 1, 'friendly green')
mob(10, true, 2, true); assert(D.ReactionColor('target') == nil, 'player => nil (class/green rule)')
mob(10, true, secret(2)); assert(D.ReactionColor('target') == nil, 'secret reaction => nil')

print('PASS: SkullCount, IsOverLevel, IsDangerous, RowText, ReactionColor; secret-safe')