# ElvUI Forever

ElvUI plugin for WoW 3.3.5a (ElvUI 6.x backport): the unit frame bars get the look of the
Forever Modern nameplates of the TidyPlates_WoTLK fork - a dark
rounded background with a light rim, a left-to-right gradient fill and a matching castbar.

Only hooks, ElvUI itself is not modified, so ElvUI updates keep working.

## Units

Player, target, target of target, focus, focus target, pet, party (incl. party pets and
targets) and their castbars. Each one can be switched on or off in the ElvUI options
under **Forever**.

## Textures

All textures are drawn by `tools/textures.py` (Pillow) from shapes; no Blizzard art.

```
python tools/textures.py
```

## Installation

Copy (or link) the `ElvUI_Forever` folder into `Interface/AddOns`. As a new addon it is
only loaded after a full client restart.
