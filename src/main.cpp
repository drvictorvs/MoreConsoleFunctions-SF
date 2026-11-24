// MoreConsoleFunctions_SF: short console commands for Starfield.
//
// Each command is registered with ModernCommandFramework and handed, as one string of
// space-separated arguments, to a global function of the same name in MoreConsoleFunctions_SF.psc.
// The Papyrus side does the work with vanilla and Cassiopeia functions, so the same
// commands also work without this DLL:  cgf "MoreConsoleFunctions_SF.GetFormInfo" "14"
// The transporter (Teleport, its menu and countdown) is a separate mod now: Transporter-SF.
// The DLL also gives the script the functions behind GetSlotConflicts and GetLoaded3DInfo
// (Diagnostics.cpp), which read game memory Papyrus can't reach.

#include "Diagnostics.h"
#include "MCF.h"
#include "Papyrus.h"

namespace
{
	constexpr auto kScript = "MoreConsoleFunctions_SF";

	struct Command
	{
		const char* name;      // what you type in the console
		const char* function;  // global function in MoreConsoleFunctions_SF.psc
	};

	// To add a command: write `Function Name(String asArgs = "") global` in MoreConsoleFunctions_SF.psc
	// and add a line here.
	constexpr std::array kCommands{
		Command{ "GetFormInfo", "GetFormInfo" },
		Command{ "GetReferenceInfo", "GetReferenceInfo" },
		Command{ "GetMovementInfo", "GetMovementInfo" },
		Command{ "GetLeveledActorInfo", "GetLeveledActorInfo" },
		Command{ "GetItemInfo", "GetItemInfo" },
		Command{ "GetModInfo", "GetModInfo" },
		Command{ "GetPluginInfo", "GetPluginInfo" },
		Command{ "GetShipInfo", "GetShipInfo" },
		Command{ "GetQuestStageInfo", "GetQuestStageInfo" },
		Command{ "GetContainerMenuInfo", "GetContainerMenuInfo" },
		Command{ "GetSpacesuitInfo", "GetSpacesuitInfo" },
		Command{ "GetActorValueInfo", "GetActorValueInfo" },
		Command{ "GetWornInfo", "GetWornInfo" },
		Command{ "GetSlotConflicts", "GetSlotConflicts" },
		Command{ "GetLoaded3DInfo", "GetLoaded3DInfo" },
		Command{ "SetBipedSlots", "SetBipedSlots" },
		Command{ "AddBipedSlots", "AddBipedSlots" },
		Command{ "RemoveBipedSlots", "RemoveBipedSlots" },
		Command{ "SetAddonModel", "SetAddonModel" },
	};

	// MCF hands over the arguments already split (and with quotes removed); the
	// Papyrus side splits on spaces again, so they are joined back with single spaces.
	std::string JoinArgs(const MCF::simple_array<MCF::simple_string_view>& a_args)
	{
		std::string joined;
		for (std::uint64_t i = 0; i < a_args.size(); ++i) {
			const std::string_view arg = a_args[i];
			if (!joined.empty()) {
				joined += ' ';
			}
			joined += arg;
		}
		return joined;
	}

	template <std::size_t I>
	void OnCommand(const MCF::simple_array<MCF::simple_string_view>& a_args, const char*, MCF::ConsoleInterface* a_console)
	{
		const auto& command = kCommands[I];
		if (!Papyrus::Call(command.function, JoinArgs(a_args))) {
			const auto message = std::format("{}: Papyrus is not ready; you can still type cgf \"{}.{}\" \"<arguments>\"", command.name, kScript, command.function);
			a_console->PrintLn(message);
		}
	}

	void Register(const char* a_name, MCF::CommandCallback a_callback)
	{
		if (MCF::RegisterCommand(a_name, a_callback)) {
			REX::INFO("registered {}", a_name);
		} else {
			REX::WARN("could not register {}: ModernCommandFramework.dll is not loaded", a_name);
		}
	}

	template <std::size_t... I>
	void RegisterAll(std::index_sequence<I...>)
	{
		(Register(kCommands[I].name, &OnCommand<I>), ...);
	}

	void OnMessage(SFSE::MessagingInterface::Message* a_message)
	{
		if (!a_message) {
			return;
		}
		switch (a_message->type) {
		case SFSE::MessagingInterface::kPostLoad:
			// every SFSE plugin is loaded, so ModernCommandFramework.dll can be found
			RegisterAll(std::make_index_sequence<kCommands.size()>{});
			break;
		case SFSE::MessagingInterface::kPostDataLoad:
			Diagnostics::BindIfUnhooked();
			break;
		default:
			break;
		}
	}
}

SFSE_PLUGIN_LOAD(const SFSE::LoadInterface* a_sfse)
{
	// The trampoline holds the jump for the native-binding hook; hooks are installed by hand, as
	// OSF Settings and OSF UI do theirs.
	SFSE::Init(a_sfse, { .trampoline = true, .trampolineSize = 64, .hook = false });
	Diagnostics::InstallBindHook();
	SFSE::GetMessagingInterface()->RegisterListener(OnMessage);
	return true;
}
