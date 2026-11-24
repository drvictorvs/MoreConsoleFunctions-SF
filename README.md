# MoreConsoleFunctions-SF

Short console commands for Starfield, ported from `CCFE_VictorCustomScript.psc` (Skyrim):
your **GetFormInfo** and **GetReferenceInfo**, and eight new **Get…Info** commands built on
Cassiopeia Papyrus Extender. It's meant as a debugging tool: each command prints what the game
knows about a form, reference, item, plugin, ship or quest.

The transporter (`Teleport`, its menu and countdown box) was split off in 0.7.0 into its own mod,
**Transporter-SF**. Its README explains how to move your settings over and which old files to
delete from this mod's folder.

| Part | File | What it does |
|---|---|---|
| Papyrus script | `scripts/Source/MoreConsoleFunctions_SF.psc` → `Data/Scripts/MoreConsoleFunctions_SF.pex` | Does all the work, with vanilla and Cassiopeia functions. Each command is a global function taking one string of arguments, like CCFE's `sArgument`. |
| DLL functions | `scripts/Source/MoreConsoleFunctions_SFDiagnostics.psc` → `Data/Scripts/MoreConsoleFunctions_SFDiagnostics.pex` | Declares the functions the DLL gives the script for GetSlotConflicts and GetLoaded3DInfo. |
| SFSE plugin | `src/` → `Data/SFSE/Plugins/MoreConsoleFunctions_SF.dll` | Registers the short names with ModernCommandFramework and hands the arguments to the script; reads the game memory GetSlotConflicts and GetLoaded3DInfo need (`src/Diagnostics.cpp`, `src/Memory.cpp`). Only those two commands need it. |

The script works on its own, so every command except GetSlotConflicts and GetLoaded3DInfo works without the DLL:

```
cgf "MoreConsoleFunctions_SF.GetReferenceInfo" ""
cgf "MoreConsoleFunctions_SF.GetFormInfo" "14"
```

With the DLL and ModernCommandFramework installed, the same commands are:

```
GetReferenceInfo
GetFormInfo 14
```

## Requirements

- SFSE and Address Library for SFSE Plugins
- Cassiopeia Papyrus Extender (the script calls it throughout)
- ModernCommandFramework, for the short command names only
- To build: Starfield Creation Kit (Papyrus compiler); for the DLL, Visual Studio 2022 Build Tools (C++), XMake 3.0+ and Git

## Commands

Arguments are separated by spaces. A form can be `player`, a hex form ID without `0x` (`14`, `0001ABCD`), or an EditorID. Where a reference is optional, the command uses the one you clicked with the console open. GetSpacesuitInfo, GetActorValueInfo, GetWornInfo, GetSlotConflicts and GetLoaded3DInfo default to the clicked actor, or to you when nothing is selected. `?` as the first argument prints the usage line.

| Command | Arguments | Prints |
|---|---|---|
| `GetFormInfo` | `[form]` | IDs, EditorID, name, type, source and last-override plugin, weight, value, description, flags; for references also the base object, named reference flags and keywords. |
| `GetReferenceInfo` | `[reference]` | Position (cell, worldspace, location, planet, coordinates, angles), size, container, item health and mods, ownership, persistence; for actors also race, states, targets, equipped weapon, actor values; then aliases and keywords. |
| `GetMovementInfo` | `[actor]` | Movement, knock and gun state, jump height, velocity per axis. |
| `GetLeveledActorInfo` | `[actor]` | Base, leveled base, appearance source, difficulty (0–4), template use. |
| `GetItemInfo` | `[index] [stack]` | Without an index: the inventory of the selected reference (or yours) with indexes. With one: that item's base, reference, names, flags, keywords, mods and armor addons. |
| `GetModInfo` | `<object mod>` | Legendary, mod collection, loose-mod item. |
| `GetPluginInfo` | `<plugin file>` | Full, medium or small master; author; pack-in references. |
| `GetShipInfo` | `[ship]` | Ownership, whether you can pilot it, parts and blueprint entries. Defaults to the selected reference, then your home ship. |
| `GetQuestStageInfo` | `<quest> <stage>` | Log entries, completes or fails the quest, run on start or stop, done. |
| `GetContainerMenuInfo` | none | Whether the container menu is open, its mode, the selected item. |
| `GetSpacesuitInfo` | `[actor]` | Whether the game is hiding the spacesuit or helmet: the hide values (`000B120E` whole suit, `000B120D` helmet, `ActorShouldHideSpacesuitHelmetCosmeticBreathable_AV`) with base and modifiers; whether slot 35 (spacesuit) and slot 3 (clothing) are covered; equipped items whose EditorID or keywords mention a suit, helmet or pack; location and parents, settlement, interior, ship, planet atmosphere and pressure. |
| `GetActorValueInfo` | `<text> [actor] [all]` | Actor values whose EditorID contains the text (any case), with the actor's current and base value and modifiers. Searches the values stored on the actor; `all` searches every actor value in the game (slow, prints progress). |
| `GetSlotConflicts` | `[actor]` | Needs the DLL. Each worn item with its biped slots and armor addons (each addon's slots, race and extra races, whether it fits the actor's race, model path for the actor's sex); the skin and its addons; then slot by slot which item, addon and skin addon claims it, flagging two worn items on one slot, or addons of two worn items on one slot, and worn items with no addon for the actor's race. Starts with how it found the game's layout. |
| `GetLoaded3DInfo` | `[actor] [filter] [depth]` | Needs the DLL. The objects attached to the actor's loaded 3D (third person): without a filter, a tree down to `depth` (default 2) with child and geometry counts; with one, every object whose name or class contains it, with its path. Shows each object's flags; bit 0 hid objects in Fallout 4's engine. |
| `SetBipedSlots` | `<armor\|addon> <slots\|none> [actor]` | Needs the DLL. Sets an armor's or armor addon's biped slots (`35,36`, bits 0-63), then re-equips what the actor wears that uses it. |
| `AddBipedSlots` / `RemoveBipedSlots` | `<armor\|addon> <slots> [actor]` | Needs the DLL. Adds or removes slots, the same way. |
| `SetAddonModel` | `<addon> <male\|female\|both> <path>` | Needs the DLL. Sets an armor addon's model path (as the game stores it, under `Meshes`; may contain spaces), then re-equips what the selected actor (else you) wears that uses it. |
| `GetWornInfo` | `[actor]` | The actor's race (and the last plugin to edit it), then each equipped item: source and last-override plugin, equip lock, keywords, armor addons with the last plugin to edit each; then which biped slots (0–63) the worn set covers. |

## Finding out why a spacesuit or helmet doesn't show

Run them in this order, on yourself (nothing selected) or a clicked follower:

1. `GetSpacesuitInfo`. If a hide value reads 1, the game is hiding the gear on purpose: check the inventory options ("Show spacesuit in settlements", "Hide helmet in breathable areas") and any hide-suit mod. `player.setav 000B120E 0` (or `000B120D`) shows it again.
2. `GetActorValueInfo spacesuit all` and `GetActorValueInfo helmet all` find the rest of the game's hide values without knowing their IDs.
3. `GetWornInfo`. Is the suit really equipped, which plugins last edited it and its addons, and which slots the worn set covers.
4. `GetSlotConflicts`. Does each suit piece have an addon that fits your race (if not, nothing of it renders), and does another worn item (or a body mod's item) claim the same slots?
5. `GetLoaded3DInfo spacesuit` (or `helmet`, or part of the model's file name). If the suit's objects are attached, something hides them (look at the flags); if they're missing, the game never built them: no fitting addon, or the model didn't load.

## Setters: session-only edits

The setters change the base form in memory: every copy of that armor or addon changes, nothing goes into the save, and restarting the game undoes them. They are meant for trying a fix (for example taking a slot off an addon that hides your spacesuit) before making it permanent in a plugin or a runtime patcher. They write only at offsets confirmed for 1.16.244 (`ARMO+0x208`, `ARMA+0x68`, models at `ARMA+0x90`/`+0xB8`), and refuse when the game's type information doesn't put the component there. Each edit is logged in `MoreConsoleFunctions_SF.log`.

## Fixes compared with your Skyrim handlers

- **GetReferenceInfo** looped on the alias counters in its keyword section, so it never printed keywords.
- Skyrim-only fields are gone: shouts, enchantment charge, poison, mounts, warmth, magicka and stamina. Object mods replace enchantments.

## Install

1. Build or copy `MoreConsoleFunctions_SF.pex` and `MoreConsoleFunctions_SFDiagnostics.pex` into `Data/Scripts/`.
2. Put `MoreConsoleFunctions_SF.dll` in `Data/SFSE/Plugins/`. GetSlotConflicts and GetLoaded3DInfo need it; with ModernCommandFramework it also gives the short command names. The other commands work without it.

With a mod manager, make a mod whose `Data` folder holds the same layout.

## Compile the script

1. Install the Starfield Creation Kit from Steam.
2. Extract the `Scripts` folder from `Starfield\Tools\ContentResources.zip`. It holds the vanilla sources and `Starfield_Papyrus_Flags.flg`.
3. Edit the paths at the top of `compile_papyrus.bat` (including `MOD_SCRIPTS`, your mod manager's `Scripts` folder for this mod), then run it. It stops and says so if a script fails to compile; otherwise it also copies the new `.pex` files to `MOD_SCRIPTS`, and reminds you if the old transporter scripts are still there. The `.pex` files land in `dist\Data\Scripts`.

## Build the plugin

CommonLibSF lives next to the projects that use it (`Projects\commonlibsf`, `Projects\MoreConsoleFunctions-SF`, `Projects\Transporter-SF`), and `xmake.lua` includes it as `../commonlibsf`. Once, in the folder that holds the projects:

```bat
git clone https://github.com/ozooma10/commonlibsf commonlibsf
git -C commonlibsf checkout 42425651185684675b7d31d503f1b38eeb6753d3
git -C commonlibsf submodule update --init --recursive
```

Then, in this project's folder, `xmake build`.

This is OSF's fork of CommonLibSF at the same commit Transporter-SF uses. The DLL lands under `build\windows\x64\`. If you set the environment variable `XSE_SF_GAME_PATH` to your Starfield folder (or `XSE_SF_MODS_PATH` to a mod manager's mods folder), `xmake install` copies it into place. `xmake project -k vsxmake` makes a Visual Studio solution; `xmake project -k compile_commands` gives VS Code's clangd what it needs.

## Test

1. **Script alone.** In game, open the console and type `cgf "MoreConsoleFunctions_SF.GetFormInfo" "14"`. You should see the player's form details. If nothing prints, check that Cassiopeia is installed and the `.pex` is in `Data/Scripts`.
2. **DLL.** `Documents\My Games\Starfield\SFSE\Logs\MoreConsoleFunctions_SF.log` should say `Diagnostics: script functions bound on MoreConsoleFunctions_SFDiagnostics` and list each registered command (or say that ModernCommandFramework wasn't found). With ModernCommandFramework working, `GetFormInfo 14` works too.
3. **Memory readers.** `cgf "MoreConsoleFunctions_SF.GetSlotConflicts" ""` and `cgf "MoreConsoleFunctions_SF.GetLoaded3DInfo" ""`. GetSlotConflicts starts with LAYOUT lines saying what the DLL found in memory; both reports are also written to `MoreConsoleFunctions_SF.log`, which is the easiest thing to send me.

## Adding a command

1. Add `Function Name(String asArgs = "") global` to `MoreConsoleFunctions_SF.psc`, reusing `Tokens`, `Arg`, `FormFromToken`, `RefOrSelected`, `FullID` and `Print`.
2. Add `Command{ "Name", "Name" },` to `kCommands` in `src/main.cpp` and rebuild. Until then, `cgf "MoreConsoleFunctions_SF.Name" "..."` already works.

## Known limits

- **Short console commands** depend on ModernCommandFramework adding them to the console. If the console says "script command ... not found", check `ModernCommandFramework.log`: "Delayed ScriptCommands install failed after retries" means it couldn't, for every mod. The `cgf "MoreConsoleFunctions_SF.<function>" "<arguments>"` forms still work.
- **Arguments can't contain spaces.** Form IDs and EditorIDs don't, so this only matters for future commands that take free text.
- **Not in Papyrus**, so not shown yet: a base form's keywords. Armor addon slots, races and models are in GetSlotConflicts (DLL).
- **GetSlotConflicts and GetLoaded3DInfo read game memory** whose layout isn't documented, and CommonLibSF's headers are wrong for some of it on this game build (OSF found the armor's biped slots at a different offset). So they don't trust header offsets: they find each part through the type information in `Starfield.exe` (the armor's slot component, an addon's race, the skin), look for arrays whose every entry is the expected kind of form, and only read memory that is mapped and readable, with a guard if it disappears mid-read. The scene-graph offsets (names, flags, children) are the ones OSF verified on 1.16.244. Untested in game: the slot mask being 64 bits in addons too (OSF verified it for armor), the slot names (a wrong guess shows as names that don't fit), model paths being in male/female order, and the meaning of the flag bits.
- **Threads.** The DLL binds these two functions as "not callable from tasklets", which in Bethesda's script engine makes them run on the game's main thread, where the equip code changes the scene graph; they only read. `MoreConsoleFunctions_SF.log` records the thread each report ran on.
- **Armor races.** A worn item whose addons don't list your race is reported as drawing nothing; the game may also accept the race's "armor race", which isn't read.
- Reference flag names come from xEdit's Starfield definitions (REFR and ACHR records); for other forms GetFormInfo shows the flags as hex only.

## License

The plugin links CommonLibSF (GPL-3.0 with a modding exception), so the plugin source is GPL-3.0. `src/MCF.h` is adapted from ModernCommandFramework's `MCF_API.h`, which its header says may be copied into other plugins. The scene-graph offsets and the armor slot offset come from OSF's findings (`osf-animation`, `src/Util/SceneGraph.h` and `src/Equipment/EquipmentService.cpp`).
