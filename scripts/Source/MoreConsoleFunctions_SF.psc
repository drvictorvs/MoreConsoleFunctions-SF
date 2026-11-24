ScriptName MoreConsoleFunctions_SF Hidden
{Console commands ported from CCFE_VictorCustomScript (Skyrim) to Starfield.
 Every command is a global function that takes one string of space-separated arguments,
 the way CCFE passed sArgument, so it works two ways:
   - typed as a short command, through MoreConsoleFunctions_SF.dll and ModernCommandFramework:  GetFormInfo 14
   - typed with the vanilla console's CallGlobalFunction:  cgf "MoreConsoleFunctions_SF.GetFormInfo" "14"
 Where a command takes an optional reference, it falls back to the console-selected reference.
 Requires Cassiopeia Papyrus Extender. The transporter is a separate mod now (Transporter-SF).}

; =====================================================================================
; Output, arguments, forms
; =====================================================================================

Function Print(String asText) global
	CassiopeiaPapyrusExtender.PrintToConsoleLog(asText)
EndFunction

; Splits the argument string on spaces. Empty pieces (from double spaces) are kept
; here and skipped by ArgCount and Arg, so no empty array is ever created.
String[] Function Tokens(String asArgs) global
	If asArgs == ""
		Return None
	EndIf
	Return CassiopeiaPapyrusExtender.SplitStrKC(asArgs, " ")
EndFunction

Int Function ArgCount(String[] akTokens) global
	If akTokens == None
		Return 0
	EndIf
	Int count = 0
	Int i = 0
	While i < akTokens.Length
		If akTokens[i] != ""
			count += 1
		EndIf
		i += 1
	EndWhile
	Return count
EndFunction

; Returns the Nth non-empty argument (0-based), or "" when there is none.
String Function Arg(String[] akTokens, Int aiIndex) global
	If akTokens == None
		Return ""
	EndIf
	Int seen = 0
	Int i = 0
	While i < akTokens.Length
		If akTokens[i] != ""
			If seen == aiIndex
				Return akTokens[i]
			EndIf
			seen += 1
		EndIf
		i += 1
	EndWhile
	Return ""
EndFunction

; True when any argument equals asFlag (Papyrus string comparison ignores case).
Bool Function HasFlag(String[] akTokens, String asFlag) global
	Int i = 0
	Int n = ArgCount(akTokens)
	While i < n
		If Arg(akTokens, i) == asFlag
			Return True
		EndIf
		i += 1
	EndWhile
	Return False
EndFunction

; "player", a hex form ID without 0x (14, 0001ABCD, FF00012A), or an EditorID.
Form Function FormFromToken(String asToken) global
	If asToken == ""
		Return None
	EndIf
	If asToken == "player"
		Return Game.GetPlayer()
	EndIf
	Form found = CassiopeiaPapyrusExtender.GetFormByHexFormID(asToken)
	If found
		Return found
	EndIf
	Form[] byEditorID = CassiopeiaPapyrusExtender.GetFormsByEditorID(asToken, False)
	If byEditorID == None || byEditorID.Length == 0
		byEditorID = CassiopeiaPapyrusExtender.GetFormsByEditorID(asToken, True)
	EndIf
	If byEditorID != None && byEditorID.Length > 0
		Return byEditorID[0]
	EndIf
	Return None
EndFunction

; The reference named by asToken, or the console-selected reference when asToken is empty.
ObjectReference Function RefOrSelected(String asToken) global
	If asToken != ""
		Return FormFromToken(asToken) as ObjectReference
	EndIf
	Return CassiopeiaPapyrusExtender.GetConsoleRef()
EndFunction

; The actor named by asToken; with no token, the console-selected actor, else the player.
Actor Function ActorOrPlayer(String asToken) global
	If asToken != ""
		Return FormFromToken(asToken) as Actor
	EndIf
	Actor selected = CassiopeiaPapyrusExtender.GetConsoleRef() as Actor
	If selected
		Return selected
	EndIf
	Return Game.GetPlayer()
EndFunction

; EditorID [TYPE:HEXID] "Name", leaving out the parts a form doesn't have.
String Function FullID(Form akForm) global
	If akForm == None
		Return "None"
	EndIf
	String result = "[" + CassiopeiaPapyrusExtender.GetFormTypeAsString(akForm) + ":" + CassiopeiaPapyrusExtender.GetHexFormID(akForm) + "]"
	String editorID = CassiopeiaPapyrusExtender.GetFormEditorID(akForm)
	If editorID != ""
		result = editorID + " " + result
	EndIf
	String displayName
	ObjectReference asRef = akForm as ObjectReference
	If asRef
		displayName = CassiopeiaPapyrusExtender.GetReferenceName(asRef)
	Else
		displayName = CassiopeiaPapyrusExtender.GetTESFullName(akForm)
	EndIf
	If displayName != ""
		result += " \"" + displayName + "\""
	EndIf
	Return result
EndFunction

; Prints a list heading with its size and returns how many entries to show (at most aiMax).
Int Function ListHeader(String asHeading, Int aiTotal, Int aiMax) global
	Print(asHeading + " (" + aiTotal + ")")
	If aiTotal > aiMax
		Print("  - showing the first " + aiMax)
		Return aiMax
	EndIf
	Return aiTotal
EndFunction

; One list printer per array type, since Papyrus arrays don't convert between element types.
Function PrintFormList(String asHeading, Form[] akList, Int aiMax) global
	Int total = 0
	If akList != None
		total = akList.Length
	EndIf
	Int shown = ListHeader(asHeading, total, aiMax)
	Int i = 0
	While i < shown
		Print("  - #" + i + ": " + FullID(akList[i]))
		i += 1
	EndWhile
EndFunction

Function PrintKeywordList(String asHeading, Keyword[] akList, Int aiMax) global
	Int total = 0
	If akList != None
		total = akList.Length
	EndIf
	Int shown = ListHeader(asHeading, total, aiMax)
	Int i = 0
	While i < shown
		Print("  - #" + i + ": " + FullID(akList[i]))
		i += 1
	EndWhile
EndFunction

Function PrintModList(String asHeading, ObjectMod[] akList, Int aiMax) global
	Int total = 0
	If akList != None
		total = akList.Length
	EndIf
	Int shown = ListHeader(asHeading, total, aiMax)
	Int i = 0
	While i < shown
		Print("  - #" + i + ": " + FullID(akList[i]))
		i += 1
	EndWhile
EndFunction

Function PrintAddonList(String asHeading, ArmorAddon[] akList, Int aiMax) global
	Int total = 0
	If akList != None
		total = akList.Length
	EndIf
	Int shown = ListHeader(asHeading, total, aiMax)
	Int i = 0
	While i < shown
		Print("  - #" + i + ": " + FullID(akList[i]))
		i += 1
	EndWhile
EndFunction

; =====================================================================================
; GetFormInfo and GetReferenceInfo (ported from your Skyrim script)
; =====================================================================================

Function GetFormInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetFormInfo [form]   (form ID, EditorID or player; default: the selected reference)")
		Return
	EndIf
	Form target = None
	If ArgCount(args) > 0
		target = FormFromToken(Arg(args, 0))
	Else
		target = CassiopeiaPapyrusExtender.GetConsoleRef()
	EndIf
	If target == None
		Print("GetFormInfo: form not found")
		Return
	EndIf

	Print("FORM IDENTIFICATION")
	Print("  - " + FullID(target))
	Print("  - FormID (hex): " + CassiopeiaPapyrusExtender.GetHexFormID(target))
	Print("  - FormID (decimal): " + target.GetFormID())
	Print("  - EditorID: " + CassiopeiaPapyrusExtender.GetFormEditorID(target))
	Print("  - Name: " + CassiopeiaPapyrusExtender.GetTESFullName(target))
	Print("  - Type: " + CassiopeiaPapyrusExtender.GetFormTypeAsString(target) + " (" + CassiopeiaPapyrusExtender.GetFormTypeAsInt(target) + ")")
	Print("  - Source plugin: " + CassiopeiaPapyrusExtender.LookupSourcePlugin(target))
	Print("  - Last override: " + CassiopeiaPapyrusExtender.LookupLastOverriderPlugin(target))
	Print("  - Created at runtime: " + CassiopeiaPapyrusExtender.IsCreated(target))
	Print("  - Weight: " + target.GetWeight())
	Print("  - Value: " + target.GetGoldValue())
	Print("  - Known to player: " + target.PlayerKnows())
	String description = CassiopeiaPapyrusExtender.GetFormDescription(target)
	If description != ""
		Print("  - Description: " + description)
	EndIf
	Print("")
	Print("FORM FLAGS: " + CassiopeiaPapyrusExtender.GetFormFlagsAsHex(target))
	ObjectReference asRef = target as ObjectReference
	If asRef
		PrintReferenceFlags(asRef)
		Print("")
		Print("BASE OBJECT")
		Print("  - " + FullID(asRef.GetBaseObject()))
		Print("")
		PrintKeywordList("REFERENCE KEYWORDS", CassiopeiaPapyrusExtender.GetKeywords(asRef), 5)
	Else
		Print("  - flag names differ by record type; GetFormInfo names them for references only")
	EndIf
EndFunction

; Flag names for placed references (REFR) and placed NPCs (ACHR), from xEdit's Starfield definitions.
Function PrintReferenceFlags(ObjectReference akRef) global
	If akRef as Actor
		Print("  - 0x00000200 Starts Dead: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x00000200))
		Print("  - 0x00000400 Persistent: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x00000400))
		Print("  - 0x00000800 Initially Disabled: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x00000800))
		Print("  - 0x00002000 Starts Unconscious: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x00002000))
		Print("  - 0x02000000 No AI Acquire: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x02000000))
		Print("  - 0x20000000 Don't Havok Settle: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x20000000))
	Else
		Print("  - 0x00000080 Turn Off Fire: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x00000080))
		Print("  - 0x00000400 Persistent: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x00000400))
		Print("  - 0x00000800 Initially Disabled: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x00000800))
		Print("  - 0x10000000 Reflected By Auto Water: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x10000000))
		Print("  - 0x20000000 Don't Havok Settle: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x20000000))
		Print("  - 0x40000000 No Respawn: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(akRef, 0x40000000))
	EndIf
EndFunction

Function GetReferenceInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetReferenceInfo [reference]   (default: the selected reference)")
		Return
	EndIf
	ObjectReference target = RefOrSelected(Arg(args, 0))
	If target == None
		Print("GetReferenceInfo: no reference given or selected")
		Return
	EndIf

	Print("REFERENCE IDENTIFICATION")
	Print("  - " + FullID(target))
	Print("  - Base: " + FullID(target.GetBaseObject()))
	Print("")
	Print("POSITION")
	Print("  - Cell: " + FullID(target.GetParentCell()))
	Print("  - Worldspace: " + FullID(target.GetWorldSpace()))
	Print("  - Location: " + FullID(target.GetCurrentLocation()))
	Print("  - Planet: " + FullID(target.GetCurrentPlanet()))
	Print("  - In space: " + target.IsInSpace())
	Print("  - X: " + target.GetPositionX() + "  Y: " + target.GetPositionY() + "  Z: " + target.GetPositionZ())
	Print("  - Angle X: " + target.GetAngleX() + "  Y: " + target.GetAngleY() + "  Z: " + target.GetAngleZ())
	Print("")
	Print("PHYSICAL PROPERTIES")
	Print("  - Mass: " + target.GetMass())
	Print("  - Scale: " + target.GetScale())
	Print("  - Height: " + target.GetHeight() + "  Width: " + target.GetWidth() + "  Length: " + target.GetLength())
	Print("  - Destruction stage: " + target.GetCurrentDestructionStage())
	Print("")
	Print("CONTAINER PROPERTIES")
	Int itemCount = CassiopeiaPapyrusExtender.GetInventoryItemCount(target)
	Print("  - Items: " + itemCount + "  Empty: " + (itemCount == 0))
	Print("  - Open state: " + target.GetOpenState())
	Print("  - Locked: " + target.IsLocked())
	Print("  - Weight in container: " + target.GetWeightInContainer())
	Print("")
	Print("ITEM PROPERTIES")
	Print("  - Health (%): " + target.GetItemHealthPercent())
	PrintModList("  Object mods", CassiopeiaPapyrusExtender.GetReferenceMods(target, False), 8)
	Print("")
	Print("MISC PROPERTIES")
	Print("  - 3D loaded: " + target.Is3DLoaded())
	Print("  - Deleted: " + target.IsDeleted())
	Print("  - Disabled: " + target.IsDisabled())
	Print("  - Persistent: " + CassiopeiaPapyrusExtender.GetIsFormFlagSet(target, 0x00000400))
	Print("  - Actor owner: " + FullID(target.GetActorOwner()))
	Print("  - Faction owner: " + FullID(target.GetFactionOwner()))
	Print("  - Scene: " + FullID(target.GetCurrentScene()))
	Print("  - Activation blocked: " + target.IsActivationBlocked())
	Print("  - Crime to activate: " + CassiopeiaPapyrusExtender.IsCrimeToActivate(target))
	Print("")

	Actor targetActor = target as Actor
	If targetActor
		Print("ACTOR PROPERTIES")
		Print("  - Leveled base: " + FullID(targetActor.GetLeveledActorBase()))
		Print("  - Race: " + FullID(targetActor.GetRace()))
		Print("  - Crime faction: " + FullID(targetActor.GetCrimeFaction()))
		Print("  - Bribe amount: " + targetActor.GetBribeAmount())
		Print("  - Dead: " + targetActor.IsDead() + "  Ghost: " + targetActor.IsGhost() + "  Bleeding out: " + targetActor.IsBleedingOut())
		Print("  - Combat state: " + targetActor.GetCombatState() + "  Target: " + FullID(targetActor.GetCombatTarget()))
		Print("  - Package: " + FullID(targetActor.GetCurrentPackage()))
		Print("  - Dialogue target: " + FullID(targetActor.GetDialogueTarget()))
		Print("  - Flying state: " + targetActor.GetFlyingState() + "  Sit state: " + targetActor.GetSitState() + "  Sleep state: " + targetActor.GetSleepState())
		Print("  - Alarmed: " + targetActor.IsAlarmed() + "  Alerted: " + targetActor.IsAlerted())
		Print("  - Arrested: " + targetActor.IsArrested() + "  Arresting: " + targetActor.IsArrestingTarget())
		Print("  - Weapon: " + FullID(targetActor.GetEquippedWeapon(0)))
		Print("  - Shield: " + FullID(targetActor.GetEquippedShield()))
		Print("")
		PrintActorValues(target)
	EndIf

	Alias[] aliases = CassiopeiaPapyrusExtender.GetAliases(target)
	Int aliasCount = 0
	If aliases != None
		aliasCount = aliases.Length
	EndIf
	Print("REFERENCE ALIASES (" + aliasCount + ")")
	Int shown = aliasCount
	If shown > 5
		Print("  - showing the first 5")
		shown = 5
	EndIf
	Int i = 0
	While i < shown
		Alias held = aliases[i]
		Print("  - Alias " + CassiopeiaPapyrusExtender.GetAliasIndex(held) + " \"" + CassiopeiaPapyrusExtender.GetAliasName(held) + "\" of " + FullID(held.GetOwningQuest()))
		i += 1
	EndWhile
	Print("")
	; Your Skyrim handler looped on the alias counters here, so it never printed keywords.
	PrintKeywordList("REFERENCE KEYWORDS", CassiopeiaPapyrusExtender.GetKeywords(target), 5)
EndFunction

; Lists the actor values stored on the reference: current, base and the three modifiers.
Function PrintActorValues(ObjectReference akRef) global
	CassiopeiaPapyrusExtender:AVStorageEntryData[] values = CassiopeiaPapyrusExtender.GetActorValues(akRef)
	Int total = 0
	If values != None
		total = values.Length
	EndIf
	Print("ACTOR VALUES (" + total + ")")
	Int i = 0
	While i < total
		CassiopeiaPapyrusExtender:AVStorageEntryData entry = values[i]
		Print("  - " + CassiopeiaPapyrusExtender.GetFormEditorID(entry.theAV) + ": " + entry.fCurrentValue + " (base " + entry.fBaseValue + ", temp " + entry.fModifierTemporary + ", perm " + entry.fModifierPermanent + ", damage " + entry.fModifierDamage + ")")
		i += 1
	EndWhile
	Print("")
EndFunction

; =====================================================================================
; The eight suggested Get...Info commands
; =====================================================================================

Function GetMovementInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetMovementInfo [actor]   (default: the selected reference)")
		Return
	EndIf
	Actor target = RefOrSelected(Arg(args, 0)) as Actor
	If target == None
		Print("GetMovementInfo: no actor given or selected")
		Return
	EndIf
	Print("MOVEMENT: " + FullID(target))
	Print("  - Movement state: " + CassiopeiaPapyrusExtender.GetMovementState(target) + "  (above 0 = moving)")
	Print("  - Knock state: " + CassiopeiaPapyrusExtender.GetKnockStateEnum(target))
	Print("  - Gun state: " + CassiopeiaPapyrusExtender.GetActorGunState(target))
	Print("  - Jump height: " + CassiopeiaPapyrusExtender.CalculateJumpHeight(target))
	Print("  - Velocity X: " + CassiopeiaPapyrusExtender.GetVelocity(target, "x") + "  Y: " + CassiopeiaPapyrusExtender.GetVelocity(target, "y") + "  Z: " + CassiopeiaPapyrusExtender.GetVelocity(target, "z"))
EndFunction

Function GetLeveledActorInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetLeveledActorInfo [actor]   (default: the selected reference)")
		Return
	EndIf
	Actor target = RefOrSelected(Arg(args, 0)) as Actor
	If target == None
		Print("GetLeveledActorInfo: no actor given or selected")
		Return
	EndIf
	Print("LEVELED ACTOR: " + FullID(target))
	Print("  - Base object: " + FullID(target.GetBaseObject()))
	Print("  - Leveled base: " + FullID(target.GetLeveledActorBase()))
	Print("  - Appearance from: " + FullID(CassiopeiaPapyrusExtender.GetAppearanceSource(target)))
	Print("  - Difficulty: " + CassiopeiaPapyrusExtender.GetLeveledCharacterModifier(target) + "  (0-4; 4 = not leveled)")
	Print("  - Uses a template: " + CassiopeiaPapyrusExtender.GetUsesLeveledTemplate(target, -1))
EndFunction

; Without an index it lists the inventory with the indexes the other arguments take.
Function GetItemInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetItemInfo [index] [stack]   (inventory of the selected reference, or the player's)")
		Print("       GetItemInfo alone lists the items with their indexes")
		Return
	EndIf
	ObjectReference holder = CassiopeiaPapyrusExtender.GetConsoleRef()
	If holder == None
		holder = Game.GetPlayer()
	EndIf
	Form[] items = CassiopeiaPapyrusExtender.GetInventoryItems(holder, True)
	Int itemTotal = 0
	If items != None
		itemTotal = items.Length
	EndIf

	If ArgCount(args) == 0
		Print("INVENTORY of " + FullID(holder) + " (" + itemTotal + " items)")
		Int i = 0
		While i < itemTotal
			Print("  - " + i + ": " + CassiopeiaPapyrusExtender.GetDisplayNameOfItem(holder, i, 0, True) + " " + FullID(items[i]) + " (stacks: " + CassiopeiaPapyrusExtender.GetItemStackCount(holder, i) + ")")
			i += 1
		EndWhile
		Return
	EndIf

	Int index = Arg(args, 0) as Int
	Int stack = 0
	If ArgCount(args) > 1
		stack = Arg(args, 1) as Int
	EndIf
	If index < 0 || index >= itemTotal
		Print("GetItemInfo: index " + index + " is outside 0-" + (itemTotal - 1))
		Return
	EndIf

	Print("ITEM " + index + " (stack " + stack + ") in " + FullID(holder))
	Print("  - Base: " + FullID(CassiopeiaPapyrusExtender.GetNthItemBaseObject(holder, index, stack)))
	Print("  - Reference: " + FullID(CassiopeiaPapyrusExtender.GetNthItemReference(holder, index, stack)))
	Print("  - Stacks: " + CassiopeiaPapyrusExtender.GetItemStackCount(holder, index))
	String[] names = CassiopeiaPapyrusExtender.GetDisplayNameOfAllItemsInStack(holder, index, True)
	If names != None
		Int n = 0
		While n < names.Length
			Print("  - Name in stack " + n + ": " + names[n])
			n += 1
		EndWhile
	EndIf
	Print("  - Playable: " + CassiopeiaPapyrusExtender.IsNthItemPlayable(holder, index, stack))
	Print("  - Featured: " + CassiopeiaPapyrusExtender.IsNthItemFeaturedItem(holder, index, stack))
	Print("  - Weapon can't drop: " + CassiopeiaPapyrusExtender.IsNthWeaponCantDrop(holder, index, stack))
	Actor owner = holder as Actor
	If owner
		Print("  - Equip state locked: " + CassiopeiaPapyrusExtender.IsNthItemEquipStateLocked(owner, index))
	EndIf
	PrintKeywordList("  Keywords", CassiopeiaPapyrusExtender.GetKeywordsOfItem(holder, index, stack), 8)
	PrintModList("  Object mods", CassiopeiaPapyrusExtender.GetObjectModsOfItem(holder, index, stack, False), 12)
	If items[index] as Armor
		PrintAddonList("  Armor addons", CassiopeiaPapyrusExtender.GetArmorAddonsOfArmorItem(holder, index), 8)
	EndIf
EndFunction

Function GetModInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	ObjectMod target = FormFromToken(Arg(args, 0)) as ObjectMod
	If ArgCount(args) == 0 || Arg(args, 0) == "?" || target == None
		Print("Usage: GetModInfo <object mod>   (form ID or EditorID of an OMOD)")
		Return
	EndIf
	Print("OBJECT MOD: " + FullID(target))
	Print("  - Legendary: " + CassiopeiaPapyrusExtender.IsLegendaryMod(target))
	Print("  - Mod collection: " + CassiopeiaPapyrusExtender.IsModCollection(target))
	Print("  - Loose mod item: " + FullID(CassiopeiaPapyrusExtender.GetLooseMod(target)))
EndFunction

Function GetPluginInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	String plugin = Arg(args, 0)
	If plugin == "" || plugin == "?"
		Print("Usage: GetPluginInfo <plugin file>   e.g. GetPluginInfo Starfield.esm")
		Return
	EndIf
	Int pluginType = CassiopeiaPapyrusExtender.GetPluginType(plugin)
	String typeName = "unknown (" + pluginType + ")"
	If pluginType == 1
		typeName = "full"
	ElseIf pluginType == 2
		typeName = "small"
	ElseIf pluginType == 3
		typeName = "medium"
	EndIf
	Print("PLUGIN: " + plugin)
	Print("  - Type: " + typeName)
	Print("  - Full master: " + CassiopeiaPapyrusExtender.IsFullMaster(plugin) + "  Medium: " + CassiopeiaPapyrusExtender.IsMediumMaster(plugin) + "  Small: " + CassiopeiaPapyrusExtender.IsSmallMaster(plugin))
	Print("  - Author: " + CassiopeiaPapyrusExtender.GetPluginFileAuthorName(plugin))
	Print("  - References in its pack-in cells: " + CassiopeiaPapyrusExtender.GetPackInCellReferenceCount(plugin))
EndFunction

Function GetShipInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetShipInfo [ship]   (default: the selected reference, else your home ship)")
		Return
	EndIf
	ObjectReference ship = RefOrSelected(Arg(args, 0))
	If ship == None
		ship = Game.GetPlayerHomeSpaceShip()
	EndIf
	If ship == None
		Print("GetShipInfo: no ship given, selected or owned")
		Return
	EndIf
	Print("SHIP: " + FullID(ship))
	Print("  - Owned by player: " + CassiopeiaPapyrusExtender.IsPlayerOwnedShip(ship))
	Print("  - Player can pilot: " + CassiopeiaPapyrusExtender.CanPlayerPilotShip(ship))
	PrintFormList("  Parts", CassiopeiaPapyrusExtender.GetSpaceshipParts(ship), 20)
	CassiopeiaPapyrusExtender:BlueprintData[] blueprints = CassiopeiaPapyrusExtender.GetSpaceshipBlueprints(ship)
	Int total = 0
	If blueprints != None
		total = blueprints.Length
	EndIf
	Print("  Blueprint entries (" + total + ")")
	Int shown = total
	If shown > 20
		Print("  - showing the first 20")
		shown = 20
	EndIf
	Int i = 0
	While i < shown
		CassiopeiaPapyrusExtender:BlueprintData entry = blueprints[i]
		Print("  - part " + entry.iPartID + ": " + FullID(entry.PartBase) + " at " + entry.fPosX + ", " + entry.fPosY + ", " + entry.fPosZ)
		i += 1
	EndWhile
EndFunction

Function GetQuestStageInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	Quest target = FormFromToken(Arg(args, 0)) as Quest
	If ArgCount(args) < 2 || Arg(args, 0) == "?" || target == None
		Print("Usage: GetQuestStageInfo <quest> <stage>   e.g. GetQuestStageInfo MQ101 100")
		Return
	EndIf
	Int stage = Arg(args, 1) as Int
	Print("QUEST STAGE " + stage + " of " + FullID(target))
	Print("  - Quest running: " + target.IsRunning() + "  Current stage: " + target.GetStage())
	Print("  - Stage done: " + target.IsStageDone(stage))
	Print("  - Log entries: " + CassiopeiaPapyrusExtender.GetQuestStageItemCount(target, stage))
	Print("  - Completes the quest: " + CassiopeiaPapyrusExtender.CompletesQuest(target, stage, -1))
	Print("  - Fails the quest: " + CassiopeiaPapyrusExtender.FailsQuest(target, stage, -1))
	Print("  - Runs on start: " + CassiopeiaPapyrusExtender.IsRunOnStartStage(target, stage) + "  Runs on stop: " + CassiopeiaPapyrusExtender.IsRunOnStopStage(target, stage))
EndFunction

Function GetContainerMenuInfo(String asArgs = "") global
	Bool menuOpen = CassiopeiaPapyrusExtender.IsMenuOpen("ContainerMenu")
	Int mode = CassiopeiaPapyrusExtender.GetContainerMenuMode()
	String modeName = "error or unknown"
	If mode == 0
		modeName = "my inventory"
	ElseIf mode == 1
		modeName = "home ship"
	ElseIf mode == 2
		modeName = "container"
	EndIf
	Print("CONTAINER MENU")
	Print("  - Open: " + menuOpen)
	Print("  - Mode: " + mode + " (" + modeName + ")")
	Print("  - Selected item: " + FullID(CassiopeiaPapyrusExtender.GetContainerMenuSelectedItem()))
EndFunction

; =====================================================================================
; Spacesuit and helmet diagnostics
;   GetSpacesuitInfo   did the game choose to hide the gear? (hide values, worn gear, place)
;   GetActorValueInfo  find actor values by part of their EditorID, with an actor's values
;   GetWornInfo        every equipped item with its plugins, keywords and armor addons, and
;                      the biped slots the worn set covers
; =====================================================================================

; Cassiopeia's ReplaceStr returns its result in lowercase, so "replacing" a newline (which
; EditorIDs and console arguments never contain) gives the lowercase text. Falls back to the
; text as it is if that ever comes back empty.
String Function LowerCase(String asText) global
	If asText == ""
		Return ""
	EndIf
	String lowered = CassiopeiaPapyrusExtender.ReplaceStr(asText, "\n", "\n")
	If lowered == ""
		Return asText
	EndIf
	Return lowered
EndFunction

; True when asText contains asPart, ignoring case. asLowerPart is LowerCase(asPart), passed in so
; a search over many forms converts the part once.
Bool Function ContainsText(String asText, String asPart, String asLowerPart) global
	If asText == "" || asPart == ""
		Return False
	EndIf
	If CassiopeiaPapyrusExtender.FindStr(asText, asPart) >= 0
		Return True
	EndIf
	Return CassiopeiaPapyrusExtender.FindStr(LowerCase(asText), asLowerPart) >= 0
EndFunction

; The entry for akValue among the values stored on an actor (GetActorValues), or None.
CassiopeiaPapyrusExtender:AVStorageEntryData Function StoredEntry(CassiopeiaPapyrusExtender:AVStorageEntryData[] akStored, ActorValue akValue) global
	If akStored == None || akValue == None
		Return None
	EndIf
	Int i = 0
	While i < akStored.Length
		If akStored[i].theAV == akValue
			Return akStored[i]
		EndIf
		i += 1
	EndWhile
	Return None
EndFunction

; One actor value of akRef: current and base value, and the three modifiers when it is stored on
; the actor. A value never set on the actor isn't stored, and then reads as its default.
Function PrintValueLine(ObjectReference akRef, CassiopeiaPapyrusExtender:AVStorageEntryData[] akStored, Form akForm, String asNote) global
	String suffix = ""
	If asNote != ""
		suffix = "   <- " + asNote
	EndIf
	If akForm == None
		Print("  - (not found in this game)" + suffix)
		Return
	EndIf
	ActorValue value = akForm as ActorValue
	If value == None
		Print("  - " + FullID(akForm) + " is not an actor value" + suffix)
		Return
	EndIf
	String line = "  - " + FullID(value) + ": " + akRef.GetValue(value) + " (base " + akRef.GetBaseValue(value)
	CassiopeiaPapyrusExtender:AVStorageEntryData entry = StoredEntry(akStored, value)
	If entry != None
		line += ", temp " + entry.fModifierTemporary + ", perm " + entry.fModifierPermanent + ", damage " + entry.fModifierDamage + ")"
	Else
		line += ", not stored on this actor)"
	EndIf
	Print(line + suffix)
EndFunction

; True when akHere or one of its parent locations has akKeyword.
Bool Function LocationOrParentHas(Location akHere, Keyword akKeyword) global
	If akHere == None || akKeyword == None
		Return False
	EndIf
	If akHere.HasKeyword(akKeyword)
		Return True
	EndIf
	Location[] parents = akHere.GetParentLocations(None)
	If parents == None
		Return False
	EndIf
	Int i = 0
	While i < parents.Length
		If parents[i] && parents[i].HasKeyword(akKeyword)
			Return True
		EndIf
		i += 1
	EndWhile
	Return False
EndFunction

; True when an EditorID mentions a suit, helmet or pack, in any case.
Bool Function MentionsGear(String asEditorID) global
	If asEditorID == ""
		Return False
	EndIf
	String lowered = LowerCase(asEditorID)
	Return CassiopeiaPapyrusExtender.FindStr(lowered, "suit") >= 0 || CassiopeiaPapyrusExtender.FindStr(lowered, "helmet") >= 0 || CassiopeiaPapyrusExtender.FindStr(lowered, "pack") >= 0
EndFunction

Function GetSpacesuitInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetSpacesuitInfo [actor]   (default: the selected actor, else the player)")
		Return
	EndIf
	Actor target = ActorOrPlayer(Arg(args, 0))
	If target == None
		Print("GetSpacesuitInfo: that isn't an actor")
		Return
	EndIf
	CassiopeiaPapyrusExtender:AVStorageEntryData[] stored = CassiopeiaPapyrusExtender.GetActorValues(target)

	Print("SPACESUIT VISIBILITY: " + FullID(target))
	; 000B120E and 000B120D are the values the hide-suit console mods set (1 hides, 0 shows);
	; the third is set by a vanilla script on an NPC that should go helmetless where it can breathe.
	PrintValueLine(target, stored, FormFromToken("000B120E"), "whole suit hidden when 1")
	PrintValueLine(target, stored, FormFromToken("000B120D"), "helmet hidden when 1")
	PrintValueLine(target, stored, FormFromToken("ActorShouldHideSpacesuitHelmetCosmeticBreathable_AV"), "set by a vanilla script")
	Print("  - more: GetActorValueInfo spacesuit all, GetActorValueInfo helmet all")
	Print("")

	Print("WORN GEAR")
	Print("  - Slot 35 covered (the spacesuit slot in vanilla scripts): " + target.WornCoversBipedSlot(35))
	Print("  - Slot 3 covered (clothing, in the same scripts): " + target.WornCoversBipedSlot(3))
	Keyword helmetType = FormFromToken("ArmorTypeHelmet") as Keyword
	If helmetType
		Print("  - Wearing an item with ArmorTypeHelmet: " + target.WornHasKeyword(helmetType))
	Else
		Print("  - keyword ArmorTypeHelmet not found")
	EndIf
	; Equipped items whose EditorID or keywords mention a suit, helmet or pack.
	Int[] indexes = CassiopeiaPapyrusExtender.GetEquippedItemIndexes(target)
	Form[] items = CassiopeiaPapyrusExtender.GetInventoryItems(target, True)
	Int shown = 0
	Int i = 0
	While indexes != None && i < indexes.Length
		Int index = indexes[i]
		Form item = None
		If items != None && index >= 0 && index < items.Length
			item = items[index]
		EndIf
		String itemID = ""
		If item
			itemID = CassiopeiaPapyrusExtender.GetFormEditorID(item)
		EndIf
		String marks = ""
		If MentionsGear(itemID)
			marks = "EditorID"
		EndIf
		Keyword[] words = CassiopeiaPapyrusExtender.GetKeywordsOfItem(target, index, 0)
		Int k = 0
		While words != None && k < words.Length
			String wordID = CassiopeiaPapyrusExtender.GetFormEditorID(words[k])
			If MentionsGear(wordID)
				If marks != ""
					marks += ", "
				EndIf
				marks += wordID
			EndIf
			k += 1
		EndWhile
		If marks != ""
			Print("  - item " + index + ": " + CassiopeiaPapyrusExtender.GetDisplayNameOfItem(target, index, 0, True) + " " + FullID(item) + "  [" + marks + "]")
			shown += 1
		EndIf
		i += 1
	EndWhile
	If shown == 0
		Print("  - no equipped item mentions a suit, helmet or pack")
	EndIf
	Print("  - every item and slot: GetWornInfo")
	Print("")

	Print("WHERE")
	Location here = target.GetCurrentLocation()
	Print("  - Location: " + FullID(here))
	If here
		Location[] parents = here.GetParentLocations(None)
		Int p = 0
		While parents != None && p < parents.Length && p < 6
			Print("  - Parent: " + FullID(parents[p]))
			p += 1
		EndWhile
	EndIf
	Keyword settlementType = FormFromToken("LocTypeSettlement") as Keyword
	If settlementType
		Print("  - Settlement (LocTypeSettlement here or above): " + LocationOrParentHas(here, settlementType))
	EndIf
	Print("  - Interior: " + target.IsInInterior() + "  In space: " + target.IsInSpace())
	Print("  - Ship: " + FullID(target.GetCurrentShipRef()))
	Planet world = target.GetCurrentPlanet()
	If world
		Print("  - Planet: " + FullID(world) + "  atmosphere: " + FullID(world.GetAtmosphereType()) + "  pressure: " + world.GetPressure())
	EndIf
EndFunction

Function GetActorValueInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	String part = Arg(args, 0)
	If part == "" || part == "?"
		Print("Usage: GetActorValueInfo <text> [actor] [all]   e.g. GetActorValueInfo spacesuit all")
		Print("       Actor values whose EditorID contains <text> (any case), with the actor's values.")
		Print("       Searches the values stored on the actor (quick); 'all' searches every actor value in the game (slow).")
		Return
	EndIf
	Bool everyValue = HasFlag(args, "all")
	String actorToken = Arg(args, 1)
	If actorToken == "all"
		actorToken = ""
	EndIf
	Actor target = ActorOrPlayer(actorToken)
	If target == None
		Print("GetActorValueInfo: that isn't an actor")
		Return
	EndIf
	String lowerPart = LowerCase(part)
	CassiopeiaPapyrusExtender:AVStorageEntryData[] stored = CassiopeiaPapyrusExtender.GetActorValues(target)
	Int found = 0
	Int total = 0
	Int i = 0
	If everyValue
		Form[] candidates = CassiopeiaPapyrusExtender.GetAllFormsByFormType(CassiopeiaPapyrusExtender.GetFormTypeStrAsInt("AVIF"), "")
		If candidates != None
			total = candidates.Length
		EndIf
		Print("ACTOR VALUES containing \"" + part + "\" among all " + total + " in the game, for " + FullID(target))
		While i < total
			Form candidate = candidates[i]
			If ContainsText(CassiopeiaPapyrusExtender.GetFormEditorID(candidate), part, lowerPart)
				PrintValueLine(target, stored, candidate, "")
				found += 1
			EndIf
			i += 1
			If i % 1000 == 0
				Print("  ... " + i + " of " + total + " checked")
			EndIf
		EndWhile
	Else
		If stored != None
			total = stored.Length
		EndIf
		Print("ACTOR VALUES containing \"" + part + "\" among the " + total + " stored on " + FullID(target))
		While i < total
			If ContainsText(CassiopeiaPapyrusExtender.GetFormEditorID(stored[i].theAV), part, lowerPart)
				PrintValueLine(target, stored, stored[i].theAV, "")
				found += 1
			EndIf
			i += 1
		EndWhile
	EndIf
	Print("  - " + found + " found")
	If !everyValue
		Print("  - values never set on this actor aren't stored; add 'all' to search every actor value")
	EndIf
EndFunction

; Keywords and addons are read from the item's first stack; that is the equipped one unless the
; actor carries several differently modded copies of the same item.
Function GetWornInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetWornInfo [actor]   (default: the selected actor, else the player)")
		Return
	EndIf
	Actor target = ActorOrPlayer(Arg(args, 0))
	If target == None
		Print("GetWornInfo: that isn't an actor")
		Return
	EndIf
	Int[] indexes = CassiopeiaPapyrusExtender.GetEquippedItemIndexes(target)
	Form[] items = CassiopeiaPapyrusExtender.GetInventoryItems(target, True)
	Int total = 0
	If indexes != None
		total = indexes.Length
	EndIf
	Print("WORN BY " + FullID(target) + " (" + total + " equipped items)")
	Print("  Race: " + FullID(target.GetRace()) + ", last edited by " + CassiopeiaPapyrusExtender.LookupLastOverriderPlugin(target.GetRace()))
	Int i = 0
	While i < total
		Int index = indexes[i]
		Form item = None
		If items != None && index >= 0 && index < items.Length
			item = items[index]
		EndIf
		Print("")
		Print("ITEM " + index + ": " + CassiopeiaPapyrusExtender.GetDisplayNameOfItem(target, index, 0, True) + " " + FullID(item))
		If item
			Print("  - From " + CassiopeiaPapyrusExtender.LookupSourcePlugin(item) + ", last edited by " + CassiopeiaPapyrusExtender.LookupLastOverriderPlugin(item))
		EndIf
		Print("  - Equip state locked: " + CassiopeiaPapyrusExtender.IsNthItemEquipStateLocked(target, index))
		PrintKeywordList("  Keywords", CassiopeiaPapyrusExtender.GetKeywordsOfItem(target, index, 0), 16)
		If item as Armor
			ArmorAddon[] addons = CassiopeiaPapyrusExtender.GetArmorAddonsOfArmorItem(target, index)
			Int addonTotal = 0
			If addons != None
				addonTotal = addons.Length
			EndIf
			Int addonShown = ListHeader("  Armor addons", addonTotal, 12)
			Int a = 0
			While a < addonShown
				Print("  - #" + a + ": " + FullID(addons[a]) + ", last edited by " + CassiopeiaPapyrusExtender.LookupLastOverriderPlugin(addons[a]))
				a += 1
			EndWhile
		EndIf
		i += 1
	EndWhile
	Print("")

	; WornCoversBipedSlot takes the slot index, 0-63 (vanilla scripts use 3 for clothing, 35 for
	; the spacesuit).
	String covered = ""
	Int coveredCount = 0
	Int slot = 0
	While slot < 64
		If target.WornCoversBipedSlot(slot)
			covered += " " + (slot as String)
			coveredCount += 1
		EndIf
		slot += 1
	EndWhile
	Print("BIPED SLOTS COVERED (" + coveredCount + " of 64):" + covered)
	Print("  - addon slots, races and models need the DLL (not in Papyrus); GetFormInfo <addon ID> shows its plugins")
EndFunction

; =====================================================================================
; Diagnostics that need MoreConsoleFunctions_SF.dll (MoreConsoleFunctions_SFDiagnostics)
;   GetSlotConflicts  which worn item, armor addon and skin addon claims each biped slot
;   GetLoaded3DInfo   the objects actually attached to an actor's loaded 3D
; =====================================================================================

Function PrintLines(String[] akLines) global
	Int i = 0
	While akLines != None && i < akLines.Length
		Print(akLines[i])
		i += 1
	EndWhile
EndFunction

; False, after saying so, when MoreConsoleFunctions_SF.dll hasn't bound its functions (missing, too old, or
; MoreConsoleFunctions_SFDiagnostics.pex missing).
Bool Function DllReady(String asCommand) global
	If MoreConsoleFunctions_SFDiagnostics.IsAvailable()
		Return True
	EndIf
	Print(asCommand + ": needs MoreConsoleFunctions_SF.dll 0.8.0 or later and MoreConsoleFunctions_SFDiagnostics.pex / MoreConsoleFunctions_SFEdits.pex (see MoreConsoleFunctions_SF.log)")
	Return False
EndFunction

Function GetSlotConflicts(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetSlotConflicts [actor]   (default: the selected actor, else the player)")
		Return
	EndIf
	Actor target = ActorOrPlayer(Arg(args, 0))
	If target == None
		Print("GetSlotConflicts: that isn't an actor")
		Return
	EndIf
	If !DllReady("GetSlotConflicts")
		Return
	EndIf
	; The worn armor and, through Cassiopeia, each one's armor addons; the DLL reads the rest.
	Armor[] worn = new Armor[0]
	ArmorAddon[] pieces = new ArmorAddon[0]
	Int[] owners = new Int[0]
	Int[] indexes = CassiopeiaPapyrusExtender.GetEquippedItemIndexes(target)
	Form[] items = CassiopeiaPapyrusExtender.GetInventoryItems(target, True)
	Int i = 0
	While indexes != None && items != None && i < indexes.Length
		Int index = indexes[i]
		If index >= 0 && index < items.Length
			Armor wornArmor = items[index] as Armor
			If wornArmor
				worn.Add(wornArmor)
				ArmorAddon[] addons = CassiopeiaPapyrusExtender.GetArmorAddonsOfArmorItem(target, index)
				Int a = 0
				While addons != None && a < addons.Length
					pieces.Add(addons[a])
					owners.Add(worn.Length - 1)
					a += 1
				EndWhile
			EndIf
		EndIf
		i += 1
	EndWhile
	ActorBase base = target.GetLeveledActorBase()
	Int sex = -1
	If base
		sex = base.GetSex()
	EndIf
	PrintLines(MoreConsoleFunctions_SFDiagnostics.SlotReport(target, target.GetRace(), base, sex, worn, pieces, owners))
EndFunction

; Arguments in any order: an actor (form ID, EditorID or player), a depth (a number; default
; 2) and a filter (anything else). Without an actor, the selected actor or the player.
Function GetLoaded3DInfo(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?"
		Print("Usage: GetLoaded3DInfo [actor] [filter] [depth]   e.g. GetLoaded3DInfo spacesuit, GetLoaded3DInfo player 3")
		Print("       Without a filter: the tree down to depth (default 2). With one: every object whose name or class contains it.")
		Return
	EndIf
	String actorToken = ""
	String filter = ""
	Int depth = 2
	Int n = ArgCount(args)
	Int i = 0
	While i < n
		String token = Arg(args, i)
		If actorToken == "" && (token == "player" || (FormFromToken(token) as Actor) != None)
			actorToken = token
		ElseIf ((token as Int) as String) == token
			depth = token as Int
		ElseIf filter == ""
			filter = token
		EndIf
		i += 1
	EndWhile
	Actor target = ActorOrPlayer(actorToken)
	If target == None
		Print("GetLoaded3DInfo: that isn't an actor")
		Return
	EndIf
	If !DllReady("GetLoaded3DInfo")
		Return
	EndIf
	PrintLines(MoreConsoleFunctions_SFDiagnostics.Loaded3DReport(target, filter, depth))
EndFunction

; =====================================================================================
; Setters that need MoreConsoleFunctions_SF.dll (MoreConsoleFunctions_SFEdits)
;   SetBipedSlots / AddBipedSlots / RemoveBipedSlots   an armor's or armor addon's slots
;   SetAddonModel                                       an armor addon's model path
; They edit the base form in memory for this session only (nothing is saved; a restart undoes
; them), then re-equip the items the actor wears that use it, so the change shows.
; =====================================================================================

; "35,36" -> [35, 36]; "none" -> an empty list.
Int[] Function ParseSlots(String asList) global
	Int[] slots = new Int[0]
	If asList == "none"
		Return slots
	EndIf
	String[] parts = CassiopeiaPapyrusExtender.SplitStrKC(asList, ",")
	Int i = 0
	While parts != None && i < parts.Length
		If parts[i] != ""
			slots.Add(parts[i] as Int)
		EndIf
		i += 1
	EndWhile
	Return slots
EndFunction

Bool Function IsEditError(String asResult) global
	Return asResult == "" || CassiopeiaPapyrusExtender.FindStr(asResult, "error:") == 0
EndFunction

; Re-equips the worn armor that is akArmor, or that uses akAddon, so its 3D is built again.
Function ReequipUsers(Actor akActor, Armor akArmor, ArmorAddon akAddon) global
	If akActor == None
		Return
	EndIf
	Armor[] users = new Armor[0]
	Int[] indexes = CassiopeiaPapyrusExtender.GetEquippedItemIndexes(akActor)
	Form[] items = CassiopeiaPapyrusExtender.GetInventoryItems(akActor, True)
	Int i = 0
	While indexes != None && items != None && i < indexes.Length
		Int index = indexes[i]
		If index >= 0 && index < items.Length
			Armor worn = items[index] as Armor
			If worn && akArmor && worn == akArmor
				users.Add(worn)
			ElseIf worn && akAddon
				ArmorAddon[] addons = CassiopeiaPapyrusExtender.GetArmorAddonsOfArmorItem(akActor, index)
				If addons != None && addons.Find(akAddon) >= 0
					users.Add(worn)
				EndIf
			EndIf
		EndIf
		i += 1
	EndWhile
	Int u = 0
	While u < users.Length
		akActor.UnequipItem(users[u], False, True)
		akActor.EquipItem(users[u], False, True)
		u += 1
	EndWhile
	Print("  - re-equipped " + users.Length + " worn item(s) on " + FullID(akActor))
EndFunction

; An armor or armor addon from a token; a reference counts as its base object.
Form Function ArmorFormFromToken(String asToken) global
	Form found = FormFromToken(asToken)
	ObjectReference placed = found as ObjectReference
	If placed
		found = placed.GetBaseObject()
	EndIf
	If (found as Armor) || (found as ArmorAddon)
		Return found
	EndIf
	Return None
EndFunction

Function EditSlotsCommand(String asArgs, Int aiMode, String asCommand) global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?" || ArgCount(args) < 2
		Print("Usage: " + asCommand + " <armor|armor addon> <slots> [actor]   slots: 35,36 (0-63)" + StringIf(aiMode == 0, " or none", ""))
		Print("       Edits the form in memory for this session only, then re-equips what the actor (default: selected, else player) wears that uses it.")
		Return
	EndIf
	If !DllReady(asCommand)
		Return
	EndIf
	Form target = ArmorFormFromToken(Arg(args, 0))
	If target == None
		Print(asCommand + ": " + Arg(args, 0) + " isn't an armor or armor addon")
		Return
	EndIf
	String result = MoreConsoleFunctions_SFEdits.EditBipedSlots(target as Armor, target as ArmorAddon, aiMode, ParseSlots(Arg(args, 1)))
	Print(asCommand + ": " + result)
	If !IsEditError(result)
		ReequipUsers(ActorOrPlayer(Arg(args, 2)), target as Armor, target as ArmorAddon)
	EndIf
EndFunction

String Function StringIf(Bool abCondition, String asYes, String asNo) global
	If abCondition
		Return asYes
	EndIf
	Return asNo
EndFunction

Function SetBipedSlots(String asArgs = "") global
	EditSlotsCommand(asArgs, 0, "SetBipedSlots")
EndFunction

Function AddBipedSlots(String asArgs = "") global
	EditSlotsCommand(asArgs, 1, "AddBipedSlots")
EndFunction

Function RemoveBipedSlots(String asArgs = "") global
	EditSlotsCommand(asArgs, 2, "RemoveBipedSlots")
EndFunction

; SetAddonModel <armor addon> <male|female|both> <path>   (the path may contain spaces)
Function SetAddonModel(String asArgs = "") global
	String[] args = Tokens(asArgs)
	If Arg(args, 0) == "?" || ArgCount(args) < 3
		Print("Usage: SetAddonModel <armor addon> <male|female|both> <path>   e.g. SetAddonModel 0001ABCD male Clothes\\Outfit\\Body_M.nif")
		Print("       Edits the addon in memory for this session only, then re-equips what the selected actor (else the player) wears that uses it.")
		Return
	EndIf
	If !DllReady("SetAddonModel")
		Return
	EndIf
	ArmorAddon addon = ArmorFormFromToken(Arg(args, 0)) as ArmorAddon
	If addon == None
		Print("SetAddonModel: " + Arg(args, 0) + " isn't an armor addon")
		Return
	EndIf
	String which = Arg(args, 1)
	If which != "male" && which != "female" && which != "both"
		Print("SetAddonModel: say male, female or both")
		Return
	EndIf
	String path = Arg(args, 2)
	Int n = ArgCount(args)
	Int i = 3
	While i < n
		path += " " + Arg(args, i)
		i += 1
	EndWhile
	Bool changed = False
	If which != "female"
		String result = MoreConsoleFunctions_SFEdits.SetAddonModel(addon, 0, path)
		Print("SetAddonModel: " + result)
		changed = changed || !IsEditError(result)
	EndIf
	If which != "male"
		String femaleResult = MoreConsoleFunctions_SFEdits.SetAddonModel(addon, 1, path)
		Print("SetAddonModel: " + femaleResult)
		changed = changed || !IsEditError(femaleResult)
	EndIf
	If changed
		ReequipUsers(ActorOrPlayer(""), None, addon)
	EndIf
EndFunction
