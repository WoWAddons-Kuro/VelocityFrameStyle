# Velocity Frame Style

Restyles Blizzard's **own** unit frames (player, target, pet) and adds the one frame Classic never had: your **pet's target**.
Works on Classic Era and WoW Forever from a single addon.

- **Text is a small grid.** Every frame has the same rows (Name, Level, Health, Health %, Power, Power %): pick where
  each sits (name row / health bar / power bar / above / below / hidden), its alignment, size and colour. No format
  strings, no abbreviation formulas. Values that the game hides (Forever secret values) simply leave the element blank.
- **Theme + overrides.** Bar texture, font, bar background, border brightness and portrait style are set once and
  inherited by every frame; any frame can override any of them.
- **Visual pickers.** The bar-texture and font dropdowns draw every choice in that texture / font (LibSharedMedia
  textures from other addons are listed when present).
- **Pet target frame.** Clickable (left-click targets, right-click menu, key binding), placed and scaled in Edit Mode
  (saved per layout, always shown while Edit Mode is open), optional hide while your pet attacks your own target.

`/vfs` opens the options, `/vfs status` prints diagnostics. Stands down automatically if EasyFrames or another unit-frame
addon is loaded.

Frame geometry reference: Easy Frames (BSD, Mirmidonis / Usoltsev). Pet-target idea: Lazy Thom's PetTarget.