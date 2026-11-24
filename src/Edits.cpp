#include "Edits.h"

#include "Memory.h"

namespace Edits
{
	namespace
	{
		using VM = RE::BSScript::IVirtualMachine;

		constexpr auto kNativeScript = "MoreConsoleFunctions_SFEdits";

		// Offsets confirmed for 1.16.244 (project RE notes, "Worn items, biped slots and armor
		// addons"): from the game's RTTI and from the record loaders.
		constexpr std::ptrdiff_t kArmorBipedComponent = 0x200;  // BGSBipedObjectForm in TESObjectARMO
		constexpr std::ptrdiff_t kAddonBipedComponent = 0x60;   // BGSBipedObjectForm in TESObjectARMA
		constexpr std::ptrdiff_t kBipedMask = 0x08;             // u64 slot mask inside the component
		constexpr std::ptrdiff_t kAddonMaleModel = 0x90;        // BGSModelMaterialSwap (MOD2)
		constexpr std::ptrdiff_t kAddonFemaleModel = 0xB8;      // BGSModelMaterialSwap (MOD3)
		constexpr std::ptrdiff_t kModelPath = 0x08;             // TESModel::model, BSFixedString

		enum class Mode : std::int32_t
		{
			kSet = 0,
			kAdd = 1,
			kRemove = 2,
		};

		std::string Label(const RE::TESForm* a_form)
		{
			if (!a_form) {
				return "None";
			}
			const char* editorID = a_form->GetFormEditorID();
			return editorID && editorID[0] ? std::format("{} [{:08X}]", editorID, a_form->GetFormID()) :
			                                 std::format("[{:08X}]", a_form->GetFormID());
		}

		std::string SlotList(std::uint64_t a_mask)
		{
			std::string result;
			for (int slot = 0; slot < 64; ++slot) {
				if (a_mask & (1ull << slot)) {
					result += (result.empty() ? "" : ",") + std::to_string(slot);
				}
			}
			return result.empty() ? "none" : result;
		}

		// The slot mask of a form, after checking against the game's type information that the
		// biped component really is where the notes say: a write to a wrong offset would corrupt
		// the form, so any doubt refuses the edit.
		std::uint64_t* SlotMask(RE::TESForm* a_form, std::ptrdiff_t a_component, std::string& a_problem)
		{
			const auto found = Memory::BaseOffset(a_form, "BGSBipedObjectForm");
			if (!found || *found != a_component) {
				a_problem = found ? std::format("its slot component is at +0x{:X}, not +0x{:X}: not editing", *found, a_component) :
				                    "its slot component couldn't be found: not editing";
				return nullptr;
			}
			return reinterpret_cast<std::uint64_t*>(Memory::Addr(a_form) + a_component + kBipedMask);
		}

		RE::BSFixedString EditBipedSlots(VM&, std::uint32_t, std::monostate, RE::TESObjectARMO* a_armor, RE::TESObjectARMA* a_addon, std::int32_t a_mode, std::vector<std::int32_t> a_slots)
		{
			RE::TESForm*   form = a_armor ? static_cast<RE::TESForm*>(a_armor) : static_cast<RE::TESForm*>(a_addon);
			const auto     component = a_armor ? kArmorBipedComponent : kAddonBipedComponent;
			std::string    problem;
			std::string    result;
			if (!form) {
				result = "error: no armor or armor addon";
			} else if (const auto mask = SlotMask(form, component, problem); !mask) {
				result = "error: " + Label(form) + ": " + problem;
			} else {
				std::uint64_t bits = 0;
				for (const auto slot : a_slots) {
					if (slot < 0 || slot > 63) {
						return RE::BSFixedString(std::format("error: slot {} is outside 0-63", slot).c_str());
					}
					bits |= 1ull << slot;
				}
				const auto before = *mask;
				switch (static_cast<Mode>(a_mode)) {
				case Mode::kAdd:
					*mask = before | bits;
					break;
				case Mode::kRemove:
					*mask = before & ~bits;
					break;
				default:
					*mask = bits;
					break;
				}
				result = std::format("{} {}: slots {} -> {}", a_armor ? "armor" : "addon", Label(form), SlotList(before), SlotList(*mask));
			}
			REX::INFO("Edits: {}", result);
			return RE::BSFixedString(result.c_str());
		}

		RE::BSFixedString SetAddonModel(VM&, std::uint32_t, std::monostate, RE::TESObjectARMA* a_addon, std::int32_t a_sex, RE::BSFixedString a_path)
		{
			std::string result;
			if (!a_addon) {
				result = "error: no armor addon";
			} else if (a_sex != 0 && a_sex != 1) {
				result = "error: sex must be 0 (male) or 1 (female)";
			} else {
				const auto offset = a_sex == 0 ? kAddonMaleModel : kAddonFemaleModel;
				const auto members = Memory::MemberOffsets(a_addon, 0x100, "BGSModelMaterialSwap");
				if (std::ranges::find(members, offset) == members.end()) {
					result = std::format("error: {}: no model component at +0x{:X}: not editing", Label(a_addon), offset);
				} else {
					auto&       model = *reinterpret_cast<RE::BSFixedString*>(Memory::Addr(a_addon) + offset + kModelPath);
					std::string before = model.c_str() ? model.c_str() : "";
					model = a_path.c_str() ? a_path.c_str() : "";
					result = std::format("addon {} {} model: \"{}\" -> \"{}\"", Label(a_addon), a_sex == 0 ? "male" : "female", before, model.c_str() ? model.c_str() : "");
				}
			}
			REX::INFO("Edits: {}", result);
			return RE::BSFixedString(result.c_str());
		}
	}

	void Bind(VM& a_vm)
	{
		// Not callable from tasklets: they run on the game's main thread, where forms are read.
		a_vm.BindNativeMethod(kNativeScript, "EditBipedSlots", &EditBipedSlots, false, false);
		a_vm.BindNativeMethod(kNativeScript, "SetAddonModel", &SetAddonModel, false, false);
		REX::INFO("Edits: script functions bound on {}", kNativeScript);
	}
}
