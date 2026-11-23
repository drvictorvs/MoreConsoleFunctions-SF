ScriptName MoreConsoleFunctions_SFDiagnostics Native Hidden
{Functions provided by MoreConsoleFunctions_SF.dll for the commands that need to read game memory Papyrus can't
 reach (GetSlotConflicts, GetLoaded3DInfo). The reports come back as lines; MoreConsoleFunctions_SF.psc prints
 them, and the DLL also writes them to MoreConsoleFunctions_SF.log.}

; True once the DLL has bound these functions; a missing or older DLL leaves this unbound (false).
Bool Function IsAvailable() global native

; The DLL's version, e.g. "0.7.2".
String Function DllVersion() global native

; Which worn item, armor addon and skin addon claims each biped slot, and where they overlap.
; akAddons are the worn items' addons (from Cassiopeia), aiAddonOwners the index in akWorn each
; belongs to. aiSex: 0 male, 1 female, -1 unknown.
String[] Function SlotReport(ObjectReference akActor, Race akRace, ActorBase akBase, Int aiSex, Armor[] akWorn, ArmorAddon[] akAddons, Int[] aiAddonOwners) global native

; The objects attached to the reference's loaded 3D: a tree down to aiMaxDepth, or, with
; asFilter, every object whose name or class contains it, with its path.
String[] Function Loaded3DReport(ObjectReference akRef, String asFilter, Int aiMaxDepth) global native
