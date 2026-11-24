#pragma once

// The functions MoreConsoleFunctions_SF.dll gives the script MoreConsoleFunctions_SFEdits:
// setters for armor and armor-addon biped slots and armor-addon model paths.
//
// They change the base forms in memory, for this game session only: nothing is saved, every
// copy of the form is affected, and a restart undoes them. The script re-equips worn items
// afterwards so the change shows.
namespace Edits
{
	// Binds the script functions on a_vm (called from the same VM hook as the diagnostics).
	void Bind(RE::BSScript::IVirtualMachine& a_vm);
}
