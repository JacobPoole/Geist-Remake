# GeistRemake

A WoW Forever addon. While you hold a keybind, a 5x5 grid of action buttons appears centered on your mouse. When you let go of the key, the grid disappears. It works in combat.

## Install

Copy the `Geist-Remake` folder (the one with `Geist-Remake.toc` inside it) into:

```
World of Warcraft\_forever_\Interface\AddOns\
```

If you can't find the folder, open Battle.net, click the gear next to Play, and choose **Show in Explorer**.

## Setup

1. **Keybind:** Open Options > Keybindings > AddOns > GeistRemake > "Show Geist Grid (hold)" and set a key.
2. **Fill the grid:** Type `/geist show` to keep the grid open. Drag spells, items, or macros onto it, then type `/geist hide`.
3. **Use it:** Hold the key, move your mouse to a button, click it, and release the key.

## Commands

| Command | What it does |
| --- | --- |
| `/geist show` | Keep the grid open so you can set it up |
| `/geist hide` | Close the grid |
| `/geist slot <n>` | First action slot the grid uses (default 145, which uses slots 145-169) |
| `/geist scale <n>` | Grid size, e.g. `0.8` or `1.2` |
| `/geist reset` | Restore the defaults |

## Notes

- The grid stores its buttons in normal action-bar slots. The default slots, 145-169, are the same slots as **Action Bars 6 and 7**. If you use those bars, either turn them off in Edit Mode or move the grid with `/geist slot <n>` to slots you don't use.
- Settings such as slot and scale are changed out of combat.
