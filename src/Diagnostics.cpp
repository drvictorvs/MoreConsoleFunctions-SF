#include "Diagnostics.h"

#include "Edits.h"
#include "Memory.h"

#include <unordered_map>
#include <unordered_set>

namespace Diagnostics
{
	namespace
	{
		using VM = RE::BSScript::IVirtualMachine;
		using Lines = std::vector<std::string>;

		constexpr auto kNativeScript = "MoreConsoleFunctions_SFDiagnostics";

		// The BindEverythingToScript call in GameVM's constructor: the same place OSF Settings and
		// OSF UI hook to bind their natives. Hooks there chain, so all of them run.
		constexpr std::ptrdiff_t kBindCallOffset = 0x802;

		std::optional<REL::THook<void(VM**)>> g_bindHook;

		// How far into a form the scans for member arrays and models look. Generous on purpose:
		// CommonLibSF's sizes (ARMA 0x280, ARMO 0x378) aren't checked for this game build, and
		// every candidate is validated through the game's type information before it is used.
		constexpr std::size_t kAddonScanSize = 0x300;
		constexpr std::size_t kArmorScanSize = 0x400;

		// ---- small helpers --------------------------------------------------------------------

		std::string Label(const RE::TESForm* a_form)
		{
			if (!a_form) {
				return "None";
			}
			const char* editorID = a_form->GetFormEditorID();
			if (editorID && editorID[0]) {
				return std::format("{} [{:08X}]", editorID, a_form->GetFormID());
			}
			return std::format("[{:08X}]", a_form->GetFormID());
		}

		std::string Lower(std::string_view a_text)
		{
			std::string result(a_text);
			for (auto& c : result) {
				c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
			}
			return result;
		}

		bool Contains(std::string_view a_text, std::string_view a_lowerPart)
		{
			return !a_lowerPart.empty() && Lower(a_text).find(a_lowerPart) != std::string::npos;
		}

		std::string SlotList(std::uint64_t a_mask)
		{
			std::string result;
			for (int slot = 0; slot < 64; ++slot) {
				if (a_mask & (1ull << slot)) {
					if (!result.empty()) {
						result += ", ";
					}
					result += std::to_string(slot);
				}
			}
			return result.empty() ? "none" : result;
		}

		std::vector<RE::BSFixedString> Finish(const char* a_report, const Lines& a_lines)
		{
			std::vector<RE::BSFixedString> result;
			result.reserve(a_lines.size());
			REX::INFO("{} ({} lines, game thread {}):", a_report, a_lines.size(), REX::W32::GetCurrentThreadId());
			for (const auto& line : a_lines) {
				REX::INFO("  {}", line);
				result.emplace_back(line.c_str());
			}
			return result;
		}

		// ---- form layout, found through the game's type information ---------------------------

		// The biped slots of an armor or armor addon: BGSBipedObjectForm keeps them as a 64-bit
		// mask right after its vtable (OSF read it at ARMO+0x208 on 1.16.244: component at 0x200).
		std::optional<std::uint64_t> BipedSlots(const RE::TESForm* a_form, std::ptrdiff_t* a_componentAt = nullptr)
		{
			const auto offset = Memory::BaseOffset(a_form, "BGSBipedObjectForm");
			std::uint64_t mask = 0;
			if (!offset || !Memory::Read(Memory::Addr(a_form) + *offset + 8, mask)) {
				return std::nullopt;
			}
			if (a_componentAt) {
				*a_componentAt = *offset;
			}
			return mask;
		}

		// The form a component points to: TESRaceForm (an addon's race) and BGSSkinForm (an NPC's
		// or race's skin) both hold one form pointer right after their vtable.
		const RE::TESForm* ComponentForm(const RE::TESForm* a_form, std::string_view a_component, std::string_view a_class)
		{
			const auto offset = a_form ? Memory::BaseOffset(a_form, a_component) : std::nullopt;
			std::uintptr_t pointer = 0;
			if (!offset || !Memory::Read(Memory::Addr(a_form) + *offset + 8, pointer) || !pointer) {
				return nullptr;
			}
			const auto form = reinterpret_cast<const RE::TESForm*>(pointer);
			return Memory::IsA(form, a_class) ? form : nullptr;
		}

		// A BSTArray (u32 size, u32 capacity, element pointer) inside a_object whose every element
		// holds, at a_pointerAt, an object of class a_class. Its offset goes to a_foundAt.
		std::optional<std::vector<const RE::TESForm*>> FormArray(const void* a_object, std::size_t a_size, std::size_t a_stride, std::size_t a_pointerAt, std::string_view a_class, std::ptrdiff_t* a_foundAt = nullptr)
		{
			const auto object = Memory::Addr(a_object);
			for (std::size_t offset = 0x10; offset + 0x10 <= a_size; offset += 8) {
				std::uint32_t  size = 0;
				std::uint32_t  capacity = 0;
				std::uintptr_t data = 0;
				if (!Memory::Read(object + offset, size) || size == 0 || size > 64 ||
					!Memory::Read(object + offset + 4, capacity) || capacity < size || capacity > 4096 ||
					!Memory::Read(object + offset + 8, data) || !Memory::Readable(data, size * a_stride)) {
					continue;
				}
				std::vector<const RE::TESForm*> forms;
				for (std::uint32_t i = 0; i < size; ++i) {
					std::uintptr_t pointer = 0;
					if (!Memory::Read(data + i * a_stride + a_pointerAt, pointer) || !Memory::IsA(reinterpret_cast<const void*>(pointer), a_class)) {
						forms.clear();
						break;
					}
					forms.push_back(reinterpret_cast<const RE::TESForm*>(pointer));
				}
				if (forms.size() == size) {
					if (a_foundAt) {
						*a_foundAt = static_cast<std::ptrdiff_t>(offset);
					}
					return forms;
				}
			}
			return std::nullopt;
		}

		// Model paths of an armor addon, in memory order: the first two are expected to be the
		// male and female biped models (CommonLibSF's order), then first-person and others.
		std::vector<std::string> ModelPaths(const RE::TESForm* a_addon)
		{
			auto offsets = Memory::MemberOffsets(a_addon, kAddonScanSize, "BGSModelMaterialSwap");
			std::vector<std::string> paths;
			for (const auto offset : offsets) {
				paths.push_back(Memory::FixedString(Memory::Addr(a_addon) + offset + 8));  // TESModel::model
			}
			return paths;
		}

		// ---- the race's biped slot names ------------------------------------------------------

		struct SlotNames
		{
			std::array<std::string, 64> names{};
			std::ptrdiff_t              offset{ -1 };
		};

		std::optional<std::array<std::string, 64>> SlotNamesAt(const RE::TESForm* a_race, std::ptrdiff_t a_offset)
		{
			std::array<std::string, 64> names{};
			int                         named = 0;
			for (int i = 0; i < 64; ++i) {
				bool ok = false;
				names[i] = Memory::FixedString(Memory::Addr(a_race) + a_offset + i * 8, &ok);
				if (!ok || names[i].size() > 64) {
					return std::nullopt;
				}
				named += names[i].empty() ? 0 : 1;
			}
			if (named < 8) {
				return std::nullopt;
			}
			return names;
		}

		// TESRace::bipedObjectNames (64 BSFixedStrings). CommonLibSF puts it at +0x160; when that
		// doesn't read as 64 names, the race is searched for a block that does. Among several
		// candidates (a block shifted by one also reads as names when its edge is empty), the one
		// whose slot 35 mentions the spacesuit wins: vanilla scripts use 35 for the spacesuit.
		SlotNames FindSlotNames(const RE::TESForm* a_race)
		{
			static std::unordered_map<const RE::TESForm*, SlotNames> cache;
			if (!a_race) {
				return {};
			}
			if (const auto it = cache.find(a_race); it != cache.end()) {
				return it->second;
			}
			constexpr std::ptrdiff_t kHeaderOffset = 0x160;
			std::vector<SlotNames>   candidates;
			for (std::ptrdiff_t offset = 0x100; offset <= 0x400 && !Memory::OutOfTime(); offset += 8) {
				if (auto names = SlotNamesAt(a_race, offset)) {
					candidates.push_back({ *names, offset });
				}
			}
			SlotNames chosen;
			for (const auto& candidate : candidates) {
				if (Contains(candidate.names[35], "suit")) {
					chosen = candidate;
					break;
				}
			}
			if (chosen.offset < 0) {
				for (const auto& candidate : candidates) {
					if (candidate.offset == kHeaderOffset) {
						chosen = candidate;
					}
				}
			}
			if (chosen.offset < 0 && !candidates.empty()) {
				chosen = candidates.front();
			}
			if (!Memory::OutOfTime()) {
				cache.emplace(a_race, chosen);
			}
			return chosen;
		}

		// ---- GetSlotConflicts -----------------------------------------------------------------

		struct Addon
		{
			const RE::TESForm*              form{ nullptr };
			int                             owner{ -1 };  // index of its worn item; -1 = the skin
			std::optional<std::uint64_t>    slots;
			const RE::TESForm*              race{ nullptr };
			std::optional<std::vector<const RE::TESForm*>> extraRaces;
			std::vector<std::string>        models;
			int                             matches{ -1 };  // 1 yes, 0 no, -1 can't tell
		};

		Addon ReadAddon(const RE::TESForm* a_form, int a_owner, const RE::TESForm* a_actorRace)
		{
			Addon addon;
			addon.form = a_form;
			addon.owner = a_owner;
			addon.slots = BipedSlots(a_form);
			addon.race = ComponentForm(a_form, "TESRaceForm", "TESRace");
			addon.extraRaces = FormArray(a_form, kAddonScanSize, 8, 0, "TESRace");
			addon.models = ModelPaths(a_form);
			if (a_actorRace) {
				const bool listed = addon.race == a_actorRace ||
				                    (addon.extraRaces && std::ranges::find(*addon.extraRaces, a_actorRace) != addon.extraRaces->end());
				addon.matches = listed ? 1 : (addon.race ? 0 : -1);
			}
			return addon;
		}

		std::string AddonLine(const Addon& a_addon, int a_sex)
		{
			std::string line = "      piece " + Label(a_addon.form) + "  slots " + (a_addon.slots ? SlotList(*a_addon.slots) : "?");
			line += "  race " + (a_addon.race ? Label(a_addon.race) : std::string("?"));
			if (a_addon.extraRaces) {
				line += std::format(" + {} more", a_addon.extraRaces->size());
			}
			line += a_addon.matches == 1 ? "  fits: yes" : a_addon.matches == 0 ? "  fits: NO" : "  fits: ?";
			if (a_sex >= 0 && static_cast<std::size_t>(a_sex) < a_addon.models.size()) {
				const auto& model = a_addon.models[a_sex];
				line += "  model: " + (model.empty() ? std::string("(none)") : model);
			} else if (!a_addon.models.empty()) {
				line += "  model: " + a_addon.models.front();
			}
			return line;
		}

		Lines BuildSlotReport(RE::TESObjectREFR* a_actor, RE::TESRace* a_race, RE::TESNPC* a_base, std::int32_t a_sex,
			const std::vector<RE::TESObjectARMO*>& a_worn, const std::vector<RE::TESObjectARMA*>& a_addons, const std::vector<std::int32_t>& a_owners)
		{
			Lines lines;
			const auto sexName = a_sex == 0 ? "male" : a_sex == 1 ? "female" : "sex unknown";
			lines.push_back(std::format("SLOT CONFLICTS: {}, race {}, {}", Label(a_actor), Label(a_race), sexName));

			REX::INFO("SlotReport: slot names");
			const auto slotNames = FindSlotNames(a_race);
			auto       slotLabel = [&](int a_slot) {
                const auto& name = slotNames.offset >= 0 ? slotNames.names[a_slot] : std::string{};
                return name.empty() ? std::to_string(a_slot) : std::format("{} \"{}\"", a_slot, name);
			};

			// The skin: the NPC's own, else the race's (what TESNPC::GetSkin does).
			REX::INFO("SlotReport: skin and worn items");
			const RE::TESForm* skin = ComponentForm(a_base, "BGSSkinForm", "TESObjectARMO");
			const char*        skinFrom = "the NPC";
			if (!skin) {
				skin = ComponentForm(a_race, "BGSSkinForm", "TESObjectARMO");
				skinFrom = "the race";
			}

			// Worn items (the skin itself sometimes shows up among them; it's reported as the skin).
			struct Worn
			{
				const RE::TESForm*           form;
				std::optional<std::uint64_t> slots;
			};
			std::vector<Worn> worn;
			std::ptrdiff_t    armorSlotsAt = -1;
			for (const auto armor : a_worn) {
				std::ptrdiff_t at = -1;
				worn.push_back({ armor, armor ? BipedSlots(armor, &at) : std::nullopt });
				if (armorSlotsAt < 0 && at >= 0) {
					armorSlotsAt = at;
				}
			}

			REX::INFO("SlotReport: armor addons");
			std::vector<Addon> addons;
			for (std::size_t i = 0; i < a_addons.size(); ++i) {
				const int owner = i < a_owners.size() ? a_owners[i] : -1;
				if (a_addons[i] && owner >= 0 && static_cast<std::size_t>(owner) < worn.size() && worn[owner].form != skin) {
					addons.push_back(ReadAddon(a_addons[i], owner, a_race));
				}
			}

			// Check the in-memory addon list against Cassiopeia's for the worn items, then use it
			// for the skin, which isn't an inventory item Cassiopeia can read.
			REX::INFO("SlotReport: addon lists");
			int            listsChecked = 0;
			int            listsMatching = 0;
			std::ptrdiff_t addonListAt = -1;
			for (std::size_t w = 0; w < worn.size(); ++w) {
				if (!worn[w].form || worn[w].form == skin) {
					continue;
				}
				std::vector<const RE::TESForm*> expected;
				for (std::size_t i = 0; i < a_addons.size(); ++i) {
					if (i < a_owners.size() && a_owners[i] == static_cast<std::int32_t>(w) && a_addons[i]) {
						expected.push_back(a_addons[i]);
					}
				}
				if (expected.empty()) {
					continue;
				}
				++listsChecked;
				std::ptrdiff_t at = -1;
				const auto     found = FormArray(worn[w].form, kArmorScanSize, 16, 8, "TESObjectARMA", &at);
				if (found && std::ranges::is_permutation(*found, expected)) {
					++listsMatching;
					addonListAt = at;
				}
			}
			std::vector<Addon>              skinAddons;
			std::optional<std::uint64_t>    skinSlots;
			std::ptrdiff_t                  skinListAt = -1;
			if (skin) {
				skinSlots = BipedSlots(skin);
				if (const auto found = FormArray(skin, kArmorScanSize, 16, 8, "TESObjectARMA", &skinListAt)) {
					for (const auto form : *found) {
						skinAddons.push_back(ReadAddon(form, -1, a_race));
					}
				}
			}

			lines.push_back("LAYOUT (found at run time; CommonLibSF's offsets aren't trusted for this game build)");
			lines.push_back(armorSlotsAt >= 0 ?
			                    std::format("  - armor biped slots: component at +0x{:X} (OSF found +0x200 on 1.16.244)", armorSlotsAt) :
			                    "  - armor biped slots: component not found; slots shown as ?");
			lines.push_back(listsChecked ?
			                    std::format("  - armor addon list in memory: at +0x{:X}, same as Cassiopeia's for {} of {} worn items", addonListAt, listsMatching, listsChecked) :
			                    "  - armor addon list in memory: no worn item with addons to check it against");
			lines.push_back(slotNames.offset >= 0 ?
			                    std::format("  - slot names: race +0x{:X} (unverified; a wrong offset shows as names that don't fit)", slotNames.offset) :
			                    "  - slot names: not found; slots shown by number");

			// Worn items and their pieces.
			int noFit = 0;
			lines.push_back(std::format("WORN ITEMS ({})", worn.size()));
			for (std::size_t w = 0; w < worn.size(); ++w) {
				if (worn[w].form == skin && skin) {
					lines.push_back("  - " + Label(worn[w].form) + "  (the skin, listed below)");
					continue;
				}
				lines.push_back("  - " + Label(worn[w].form) + "  slots " + (worn[w].slots ? SlotList(*worn[w].slots) : "?"));
				int pieces = 0;
				int fitting = 0;
				int unknown = 0;
				for (const auto& addon : addons) {
					if (addon.owner == static_cast<int>(w)) {
						lines.push_back(AddonLine(addon, a_sex));
						++pieces;
						fitting += addon.matches == 1 ? 1 : 0;
						unknown += addon.matches < 0 ? 1 : 0;
					}
				}
				if (pieces == 0) {
					lines.push_back("      no armor addons: this item has nothing to draw");
				} else if (fitting == 0 && unknown == 0) {
					lines.push_back("      NO PIECE FOR THIS RACE: nothing of it renders, unless the race's armor race is listed (not checked)");
					++noFit;
				}
			}

			if (skin) {
				lines.push_back(std::format("SKIN {} (from {})  slots {}", Label(skin), skinFrom, skinSlots ? SlotList(*skinSlots) : "?"));
				if (skinListAt < 0) {
					lines.push_back("      its armor addons couldn't be read");
				}
				for (const auto& addon : skinAddons) {
					lines.push_back(AddonLine(addon, a_sex));
				}
			} else {
				lines.push_back("SKIN not found (neither the NPC nor the race has one that could be read)");
			}

			// Slot by slot: who claims it. Only pieces that fit the race take part in conflicts.
			int conflicts = 0;
			lines.push_back("SLOTS (worn items; pieces that fit the race; skin pieces)");
			for (int slot = 0; slot < 64; ++slot) {
				const auto bit = 1ull << slot;
				std::vector<std::string> items;
				std::vector<std::string> pieces;
				std::vector<int>         pieceOwners;
				std::vector<std::string> skinPieces;
				for (const auto& item : worn) {
					if (item.form != skin && item.slots && (*item.slots & bit)) {
						items.push_back(Label(item.form));
					}
				}
				for (const auto& addon : addons) {
					if (addon.matches != 0 && addon.slots && (*addon.slots & bit)) {
						pieces.push_back(Label(addon.form));
						if (std::ranges::find(pieceOwners, addon.owner) == pieceOwners.end()) {
							pieceOwners.push_back(addon.owner);
						}
					}
				}
				for (const auto& addon : skinAddons) {
					if (addon.matches != 0 && addon.slots && (*addon.slots & bit)) {
						skinPieces.push_back(Label(addon.form));
					}
				}
				if (items.empty() && pieces.empty() && skinPieces.empty()) {
					continue;
				}
				auto join = [](const std::vector<std::string>& a_list) {
					std::string text;
					for (const auto& entry : a_list) {
						text += (text.empty() ? "" : ", ") + entry;
					}
					return text.empty() ? std::string("-") : text;
				};
				std::string line = "  - " + slotLabel(slot) + ": items " + join(items) + "; pieces " + join(pieces) + "; skin " + join(skinPieces);
				if (!skinPieces.empty()) {
					line += pieces.empty() ? " (skin shows)" : " (covered)";
				}
				lines.push_back(line);
				if (items.size() > 1) {
					lines.push_back(std::format("      CONFLICT: {} worn items claim this slot", items.size()));
					++conflicts;
				}
				if (pieceOwners.size() > 1) {
					lines.push_back(std::format("      CONFLICT: pieces of {} different worn items claim this slot; only one draws here", pieceOwners.size()));
					++conflicts;
				}
			}
			lines.push_back(std::format("SUMMARY: {} conflicts, {} worn items with no piece for this race", conflicts, noFit));
			lines.push_back("  Which piece wins a shared slot depends on equip order and addon priority, which this report doesn't read.");
			return lines;
		}

		// ---- GetLoaded3DInfo ------------------------------------------------------------------

		// NiAVObject and NiNode fields as OSF verified them on 1.16.244 (its Util/SceneGraph.h):
		// name at +0x10, flags at +0x118; children array pointer at +0x138, its used size at
		// +0x142 and capacity at +0x140, with null holes.
		constexpr std::ptrdiff_t kName = 0x10;
		constexpr std::ptrdiff_t kFlags = 0x118;
		constexpr std::ptrdiff_t kChildren = 0x138;
		constexpr std::ptrdiff_t kChildrenCapacity = 0x140;
		constexpr std::ptrdiff_t kChildrenSize = 0x142;

		struct SceneObject
		{
			std::uintptr_t address{ 0 };
			int            parent{ -1 };
			int            depth{ 0 };
			std::string    name;
			std::string    type;
			std::uint64_t  flags{ 0 };
			bool           flagsRead{ false };
			bool           node{ false };
			bool           geometry{ false };
			int            children{ 0 };
			int            below{ 0 };
			int            geometryBelow{ 0 };
			int            flaggedBelow{ 0 };
		};

		std::vector<SceneObject> WalkScene(std::uintptr_t a_root, std::size_t a_limit, int& a_unreadable)
		{
			std::vector<SceneObject>                        objects;
			std::vector<std::tuple<std::uintptr_t, int, int>> stack{ { a_root, -1, 0 } };
			std::unordered_set<std::uintptr_t>              seen;
			while (!stack.empty() && objects.size() < a_limit) {
				const auto [address, parent, depth] = stack.back();
				stack.pop_back();
				if (!address || !seen.insert(address).second) {
					continue;
				}
				const auto  pointer = reinterpret_cast<const void*>(address);
				SceneObject object;
				object.address = address;
				object.parent = parent;
				object.depth = depth;
				object.type = Memory::TypeName(pointer);
				if (object.type.empty()) {
					++a_unreadable;
					continue;  // not an object with readable type information: don't trust its fields
				}
				object.name = Memory::FixedString(address + kName);
				object.flagsRead = Memory::Read(address + kFlags, object.flags);
				object.node = Memory::IsA(pointer, "NiNode");
				object.geometry = Memory::IsA(pointer, "BSGeometry");
				const int index = static_cast<int>(objects.size());
				if (object.node && depth < 64) {
					std::uintptr_t base = 0;
					std::uint16_t  size = 0;
					std::uint16_t  capacity = 0;
					if (Memory::Read(address + kChildren, base) && Memory::Read(address + kChildrenSize, size) &&
						Memory::Read(address + kChildrenCapacity, capacity) && size <= capacity && size <= 4096 && size) {
						std::vector<std::uintptr_t> children(size);
						if (Memory::Read(base, children.data(), size * sizeof(std::uintptr_t))) {
							for (auto it = children.rbegin(); it != children.rend(); ++it) {
								if (*it) {
									stack.emplace_back(*it, index, depth + 1);
									++object.children;
								}
							}
						}
					}
				}
				objects.push_back(std::move(object));
			}
			// Totals below each object (children come after their parent in this order).
			for (auto i = objects.size(); i-- > 1;) {
				const auto& child = objects[i];
				if (child.parent < 0) {
					continue;
				}
				auto& parent = objects[child.parent];
				parent.below += 1 + child.below;
				parent.geometryBelow += (child.geometry ? 1 : 0) + child.geometryBelow;
				parent.flaggedBelow += ((child.flagsRead && (child.flags & 1)) ? 1 : 0) + child.flaggedBelow;
			}
			return objects;
		}

		std::string Describe(const SceneObject& a_object)
		{
			std::string line = (a_object.name.empty() ? std::string("(no name)") : a_object.name) + " <" + a_object.type + ">";
			if (a_object.node) {
				line += std::format("  children {}, {} below ({} geometry)", a_object.children, a_object.below, a_object.geometryBelow);
			}
			if (a_object.flagsRead) {
				line += std::format("  flags 0x{:X}{}", a_object.flags, (a_object.flags & 1) ? " BIT0" : "");
			}
			return line;
		}

		Lines BuildScene3DReport(RE::TESObjectREFR* a_ref, std::string_view a_filter, int a_maxDepth)
		{
			Lines lines;
			lines.push_back("LOADED 3D: " + Label(a_ref));
			RE::NiPointer<RE::NiAVObject> root;
			{
				const auto loaded = a_ref->loadedData.LockRead();
				if (*loaded) {
					root = (*loaded)->data3D;
				}
			}
			if (!root) {
				lines.push_back("  - no 3D loaded (is it in a loaded area?)");
				return lines;
			}
			constexpr std::size_t kLimit = 20000;
			int                   unreadable = 0;
			const auto            objects = WalkScene(Memory::Addr(root.get()), kLimit, unreadable);
			if (objects.empty()) {
				lines.push_back("  - the root couldn't be read");
				return lines;
			}
			const auto& top = objects.front();
			int         geometry = (top.geometry ? 1 : 0) + top.geometryBelow;
			int         flagged = ((top.flagsRead && (top.flags & 1)) ? 1 : 0) + top.flaggedBelow;
			lines.push_back(std::format("  - {} objects ({} geometry, {} with flag bit 0 set){}{}", objects.size(), geometry, flagged,
				objects.size() >= kLimit ? "; stopped at the limit" : "",
				unreadable ? std::format("; {} entries skipped (no type information)", unreadable) : ""));
			lines.push_back("  - flag bit 0 hid an object in Fallout 4; whether it does the same in Starfield is untested");

			constexpr std::size_t kMaxLines = 300;
			std::size_t           shown = 0;
			std::size_t           left = 0;
			const auto            filter = Lower(a_filter);
			if (filter.empty()) {
				lines.push_back(std::format("TREE to depth {} (add a filter to search all of it)", a_maxDepth));
				for (const auto& object : objects) {
					if (object.depth > a_maxDepth) {
						continue;
					}
					if (shown >= kMaxLines) {
						++left;
						continue;
					}
					lines.push_back(std::string(2 + object.depth * 2, ' ') + Describe(object));
					++shown;
				}
			} else {
				lines.push_back(std::format("MATCHES for \"{}\" (name or type)", a_filter));
				for (const auto& object : objects) {
					if (!Contains(object.name, filter) && !Contains(object.type, filter)) {
						continue;
					}
					if (shown >= kMaxLines) {
						++left;
						continue;
					}
					std::vector<std::string> path;
					for (int at = object.parent; at >= 0 && path.size() < 6; at = objects[at].parent) {
						path.push_back(objects[at].name.empty() ? "?" : objects[at].name);
					}
					std::string where;
					for (auto it = path.rbegin(); it != path.rend(); ++it) {
						where += *it + " / ";
					}
					lines.push_back("  - " + where + Describe(object));
					++shown;
				}
				if (shown == 0) {
					lines.push_back("  - nothing matches");
				}
			}
			if (left) {
				lines.push_back(std::format("  ... {} more not shown; narrow the filter or the depth", left));
			}
			return lines;
		}

		// ---- the script functions -------------------------------------------------------------

		// Each report gets this long on the game's main thread; the game is frozen meanwhile.
		constexpr std::chrono::milliseconds kBudget{ 2000 };

		void FinishBudget(Lines& a_lines)
		{
			if (Memory::OutOfTime()) {
				a_lines.push_back(std::format("STOPPED after {} s: reading took too long, so the report above is incomplete.", kBudget.count() / 1000.0));
			}
			Memory::EndBudget();
		}

		bool IsAvailable(VM&, std::uint32_t, std::monostate)
		{
			return true;
		}

		RE::BSFixedString DllVersion(VM&, std::uint32_t, std::monostate)
		{
			const auto version = SFSE::GetPluginVersion();
			return RE::BSFixedString(std::format("{}.{}.{}", version.major(), version.minor(), version.patch()).c_str());
		}

		std::vector<RE::BSFixedString> SlotReport(VM&, std::uint32_t, std::monostate, RE::TESObjectREFR* a_actor, RE::TESRace* a_race, RE::TESNPC* a_base, std::int32_t a_sex,
			std::vector<RE::TESObjectARMO*> a_worn, std::vector<RE::TESObjectARMA*> a_addons, std::vector<std::int32_t> a_owners)
		{
			Lines lines;
			Memory::StartBudget(kBudget);
			try {
				if (!a_actor) {
					lines.push_back("GetSlotConflicts: no actor");
				} else {
					lines = BuildSlotReport(a_actor, a_race, a_base, a_sex, a_worn, a_addons, a_owners);
				}
			} catch (const std::exception& e) {
				lines.push_back(std::format("GetSlotConflicts failed: {}", e.what()));
			}
			FinishBudget(lines);
			return Finish("SlotReport", lines);
		}

		std::vector<RE::BSFixedString> Loaded3DReport(VM&, std::uint32_t, std::monostate, RE::TESObjectREFR* a_ref, RE::BSFixedString a_filter, std::int32_t a_maxDepth)
		{
			Lines lines;
			Memory::StartBudget(kBudget);
			try {
				if (!a_ref) {
					lines.push_back("GetLoaded3DInfo: no reference");
				} else {
					const std::string_view filter = a_filter.c_str() ? a_filter.c_str() : "";
					lines = BuildScene3DReport(a_ref, filter, std::clamp(a_maxDepth, 0, 64));
				}
			} catch (const std::exception& e) {
				lines.push_back(std::format("GetLoaded3DInfo failed: {}", e.what()));
			}
			FinishBudget(lines);
			return Finish("Loaded3DReport", lines);
		}

		void BindNatives(VM& a_vm)
		{
			// Not callable from tasklets: the VM runs them on the game's main thread.
			a_vm.BindNativeMethod(kNativeScript, "IsAvailable", &IsAvailable, false, false);
			a_vm.BindNativeMethod(kNativeScript, "DllVersion", &DllVersion, false, false);
			a_vm.BindNativeMethod(kNativeScript, "SlotReport", &SlotReport, false, false);
			a_vm.BindNativeMethod(kNativeScript, "Loaded3DReport", &Loaded3DReport, false, false);
			REX::INFO("Diagnostics: script functions bound on {}", kNativeScript);
			Edits::Bind(a_vm);
		}

		void OnVMBind(VM** a_vm)
		{
			(*g_bindHook)(a_vm);
			if (a_vm && *a_vm) {
				BindNatives(**a_vm);  // every time: the game may build the VM more than once
			}
		}
	}

	bool InstallBindHook()
	{
		g_bindHook.emplace("MoreConsoleFunctions_SF::BindNatives", RE::ID::GameVM::Ctor, kBindCallOffset, &OnVMBind);
		if (!g_bindHook->Init()) {
			REX::ERROR("Diagnostics: native-binding hook could not be set up; binding after data load instead");
			g_bindHook.reset();
			return false;
		}
		g_bindHook->Enable();
		REX::INFO("Diagnostics: script functions will bind whenever the game builds its Papyrus VM");
		return true;
	}

	void BindIfUnhooked()
	{
		if (g_bindHook) {
			return;
		}
		if (const auto game = RE::GameVM::GetSingleton(); game && game->GetVM()) {
			BindNatives(*game->GetVM());
		}
	}
}
