ScriptName MoreConsoleFunctions_SFEdits Native Hidden
{Setters provided by MoreConsoleFunctions_SF.dll. They change base forms in memory for this game
 session only: nothing is saved, every copy of the form changes, and a restart undoes them.}

; Biped slots of an armor (akArmor) or an armor addon (akAddon; pass None for the other).
; aiMode: 0 sets the slots to aiSlots, 1 adds them, 2 removes them. Slots are 0-63.
; Returns "armor|addon <form>: slots <before> -> <after>", or a line starting "error:".
String Function EditBipedSlots(Armor akArmor, ArmorAddon akAddon, Int aiMode, Int[] aiSlots) global native

; The model path of an armor addon for one sex (0 male, 1 female), relative to Data\Meshes as the
; game stores it. Returns "addon <form> <sex> model: <before> -> <after>", or "error: ...".
String Function SetAddonModel(ArmorAddon akAddon, Int aiSex, String asPath) global native
