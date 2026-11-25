# Velocity Frame Style

Restyles Blizzard's **own** unit frames (player, target, pet) and adds the one frame Classic never had: your **pet's target**.
Works on Classic Era and WoW Forever from a single addon.

- **Text is a small grid.** Four rows: Name, Level, Health and Power. Pick position, alignment, size and colour.
  Health and Power each offer **Current**, **Current / Max**, or **Percent**; use Position = Hidden to hide a row.
  Formats are independent per bar and frame, including Forever. Forever uses Blizzard's secret-safe formatting APIs;
  the game's global Status Text setting is not changed.
- **Theme + overrides.** Bar texture, font, bar background, border brightness and portrait style are set once and
  inherited by every frame; any frame can override any of them.
- **Visual pickers.** The bar-texture and font dropdowns draw every choice in that texture / font (LibSharedMedia
  textures from other addons are listed when present).
- **Pet target frame.** Clickable (left-click targets, right-click menu, key binding), placed and scaled in Edit Mode
  (saved per layout, always shown while Edit Mode is open), optional hide while your pet attacks your own target.

`/vfs` opens the options, `/vfs status` prints diagnostics. Stands down automatically if EasyFrames or another unit-frame
addon is loaded.

Frame geometry reference: Easy Frames (BSD, Mirmidonis / Usoltsev). Pet-target idea: Lazy Thom's PetTarget.