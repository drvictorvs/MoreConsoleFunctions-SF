#pragma once

// The functions MoreConsoleFunctions_SF.dll gives the script MoreConsoleFunctions_SFDiagnostics (see MoreConsoleFunctions_SFDiagnostics.psc):
// reports the script can't build from Papyrus alone. Each returns its report as lines, which
// MoreConsoleFunctions_SF.psc prints to the console; the same lines go to MoreConsoleFunctions_SF.log.
//
//   SlotReport      which worn item, which armor addon and which skin addon claims each biped
//                   slot, and where they overlap (GetSlotConflicts)
//   Loaded3DReport  the objects attached to an actor's loaded 3D (GetLoaded3DInfo)
//
// Both are bound with "not callable from tasklets", so the game runs them on its main thread,
// where the equip pipeline changes the scene graph; they only read.
namespace Diagnostics
{
	// Binds the functions whenever the game builds its Papyrus VM (call at plugin load).
	bool InstallBindHook();

	// Binds them on the running VM if the hook couldn't be installed (call after data load).
	void BindIfUnhooked();
}
