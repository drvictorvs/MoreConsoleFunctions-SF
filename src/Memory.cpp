#include "Memory.h"

#include <chrono>
#include <cstring>
#include <mutex>
#include <unordered_map>

namespace Memory
{
	namespace
	{
		constexpr std::uint32_t kPageGuard = 0x100;

		// Copies with a structured-exception guard, so a page that goes away between the
		// readability check and the copy can't crash the game. Plain data only in here: MSVC
		// doesn't allow __try in a function that has to unwind C++ objects.
		bool CopyGuarded(void* a_out, const void* a_source, std::size_t a_size) noexcept
		{
#if defined(_MSC_VER)
			__try {
				std::memcpy(a_out, a_source, a_size);
				return true;
			} __except (1 /* EXCEPTION_EXECUTE_HANDLER */) {
				return false;
			}
#else
			std::memcpy(a_out, a_source, a_size);
			return true;
#endif
		}

		struct Image
		{
			std::uintptr_t base{ 0 };
			std::uintptr_t end{ 0 };
		};

		const Image& GetImage()
		{
			static const Image image = []() {
				Image result;
				const auto base = reinterpret_cast<std::uintptr_t>(REX::W32::GetModuleHandleW(nullptr));
				std::uint16_t mz = 0;
				std::uint32_t ntOffset = 0;
				std::uint32_t signature = 0;
				std::uint32_t sizeOfImage = 0;
				if (base && Read(base, mz) && mz == 0x5A4D && Read(base + 0x3C, ntOffset) &&
					Read(base + ntOffset, signature) && signature == 0x00004550 &&
					Read(base + ntOffset + 0x18 + 0x38, sizeOfImage)) {
					result.base = base;
					result.end = base + sizeOfImage;
				}
				return result;
			}();
			return image;
		}

		std::uintptr_t ImageBase() { return GetImage().base; }

		// x64 RTTI records; every pointer in them is an offset from the image base.
		struct CompleteObjectLocator
		{
			std::uint32_t signature;        // 1 on x64
			std::uint32_t offset;           // where this vtable's subobject sits in the object
			std::uint32_t cdOffset;
			std::uint32_t typeDescriptor;
			std::uint32_t classDescriptor;
			std::uint32_t self;
		};

		struct ClassHierarchyDescriptor
		{
			std::uint32_t signature;
			std::uint32_t attributes;
			std::uint32_t numBaseClasses;
			std::uint32_t baseClassArray;
		};

		struct BaseClassDescriptor
		{
			std::uint32_t typeDescriptor;
			std::uint32_t numContainedBases;
			std::int32_t  mdisp;  // offset of this base in the complete object
			std::int32_t  pdisp;  // -1 unless the base is virtual
			std::int32_t  vdisp;
			std::uint32_t attributes;
		};

		struct BaseInfo
		{
			std::string    name;
			std::ptrdiff_t offset;
		};

		struct ClassInfo
		{
			bool                  valid{ false };
			std::uint32_t         vtableOffset{ 0 };  // the locator's offset: 0 for a complete object's own vtable
			std::string           name;
			std::vector<BaseInfo> bases;  // the class itself first, then every non-virtual base
		};

		// ".?AVTESObjectARMA@@" -> "TESObjectARMA"; ".?AVInner@Outer@@" -> "Outer::Inner".
		std::string Demangle(std::string_view a_mangled)
		{
			if (a_mangled.starts_with(".?AV") || a_mangled.starts_with(".?AU")) {
				a_mangled.remove_prefix(4);
			} else {
				return std::string(a_mangled);
			}
			if (a_mangled.ends_with("@@")) {
				a_mangled.remove_suffix(2);
			}
			if (a_mangled.find('?') != std::string_view::npos) {
				return std::string(a_mangled);  // templates and other special names: leave as they are
			}
			std::vector<std::string_view> parts;
			std::size_t                   start = 0;
			while (start <= a_mangled.size()) {
				const auto at = a_mangled.find('@', start);
				parts.push_back(a_mangled.substr(start, at == std::string_view::npos ? std::string_view::npos : at - start));
				if (at == std::string_view::npos) {
					break;
				}
				start = at + 1;
			}
			std::string result;
			for (auto it = parts.rbegin(); it != parts.rend(); ++it) {
				if (it->empty()) {
					continue;
				}
				if (!result.empty()) {
					result += "::";
				}
				result += *it;
			}
			return result;
		}

		std::string TypeDescriptorName(std::uint32_t a_rva)
		{
			return a_rva ? Demangle(CString(ImageBase() + a_rva + 0x10, 256)) : std::string{};
		}

		ClassInfo Describe(std::uintptr_t a_vtable)
		{
			ClassInfo info;
			const auto base = ImageBase();
			std::uintptr_t locatorAddress = 0;
			if (!base || !InImage(a_vtable) || !Read(a_vtable - sizeof(void*), locatorAddress) || !InImage(locatorAddress)) {
				return info;
			}
			CompleteObjectLocator locator{};
			if (!Read(locatorAddress, locator) || locator.signature != 1 || base + locator.self != locatorAddress) {
				return info;
			}
			info.vtableOffset = locator.offset;
			info.name = TypeDescriptorName(locator.typeDescriptor);
			if (info.name.empty()) {
				return info;
			}
			ClassHierarchyDescriptor hierarchy{};
			if (Read(base + locator.classDescriptor, hierarchy)) {
				const auto count = std::min<std::uint32_t>(hierarchy.numBaseClasses, 128);
				for (std::uint32_t i = 0; i < count; ++i) {
					std::uint32_t       descriptorRva = 0;
					BaseClassDescriptor descriptor{};
					if (!Read(base + hierarchy.baseClassArray + i * sizeof(std::uint32_t), descriptorRva) ||
						!Read(base + descriptorRva, descriptor)) {
						break;
					}
					if (descriptor.pdisp != -1) {
						continue;  // virtual bases: the game's forms don't use them
					}
					info.bases.push_back({ TypeDescriptorName(descriptor.typeDescriptor), descriptor.mdisp });
				}
			}
			info.valid = true;
			return info;
		}

		// Looked up per vtable, once: a scene graph has hundreds of objects of a few classes.
		const ClassInfo& DescribeCached(std::uintptr_t a_vtable)
		{
			static std::mutex                                    lock;
			static std::unordered_map<std::uintptr_t, ClassInfo> cache;
			std::lock_guard guard(lock);
			const auto      it = cache.find(a_vtable);
			if (it != cache.end()) {
				return it->second;
			}
			return cache.emplace(a_vtable, Describe(a_vtable)).first->second;
		}

		const ClassInfo* ObjectClass(const void* a_object)
		{
			std::uintptr_t vtable = 0;
			if (!a_object || !Read(Addr(a_object), vtable) || !InImage(vtable)) {
				return nullptr;
			}
			const auto& info = DescribeCached(vtable);
			return info.valid && info.vtableOffset == 0 ? &info : nullptr;
		}
	}

	namespace
	{
		using Clock = std::chrono::steady_clock;

		thread_local bool              t_budgetSet = false;
		thread_local bool              t_outOfTime = false;
		thread_local Clock::time_point t_deadline{};
		thread_local std::uint32_t     t_checks = 0;

		// The last readable region VirtualQuery reported. Most reads land in the same few
		// regions, and asking the kernel each time is what made the first version take minutes.
		thread_local std::uintptr_t t_regionBegin = 0;
		thread_local std::uintptr_t t_regionEnd = 0;

		bool BudgetLeft() noexcept
		{
			if (!t_budgetSet) {
				return true;
			}
			if (t_outOfTime) {
				return false;
			}
			if ((++t_checks & 0xFF) == 0 && Clock::now() > t_deadline) {
				t_outOfTime = true;
				return false;
			}
			return true;
		}
	}

	void StartBudget(std::chrono::milliseconds a_limit) noexcept
	{
		t_budgetSet = true;
		t_outOfTime = false;
		t_checks = 0;
		t_deadline = Clock::now() + a_limit;
		t_regionBegin = t_regionEnd = 0;  // regions change between reports
	}

	void EndBudget() noexcept
	{
		t_budgetSet = false;
		t_regionBegin = t_regionEnd = 0;
	}

	bool OutOfTime() noexcept
	{
		return t_outOfTime;
	}

	bool Readable(std::uintptr_t a_address, std::size_t a_size) noexcept
	{
		if (a_address == 0 || a_size == 0 || a_address + a_size < a_address || !BudgetLeft()) {
			return false;
		}
		std::uintptr_t cursor = a_address;
		const auto     end = a_address + a_size;
		if (cursor >= t_regionBegin && end <= t_regionEnd) {
			return true;
		}
		while (cursor < end) {
			REX::W32::MEMORY_BASIC_INFORMATION info{};
			if (REX::W32::VirtualQuery(reinterpret_cast<const void*>(cursor), &info, sizeof(info)) == 0) {
				return false;
			}
			if (info.state != REX::W32::MEM_COMMIT) {
				return false;
			}
			if ((info.protect & kPageGuard) != 0 || (info.protect & 0xFF) == REX::W32::PAGE_NOACCESS) {
				return false;
			}
			const auto regionEnd = reinterpret_cast<std::uintptr_t>(info.baseAddress) + info.regionSize;
			if (regionEnd <= cursor) {
				return false;
			}
			t_regionBegin = reinterpret_cast<std::uintptr_t>(info.baseAddress);
			t_regionEnd = regionEnd;
			cursor = std::min(end, regionEnd);
		}
		return true;
	}

	bool Read(std::uintptr_t a_address, void* a_out, std::size_t a_size) noexcept
	{
		return Readable(a_address, a_size) && CopyGuarded(a_out, reinterpret_cast<const void*>(a_address), a_size);
	}

	bool InImage(std::uintptr_t a_address) noexcept
	{
		const auto& image = GetImage();
		return image.base != 0 && a_address >= image.base && a_address < image.end;
	}

	std::string CString(std::uintptr_t a_address, std::size_t a_max)
	{
		std::string result;
		char        chunk[16];
		while (result.size() < a_max) {
			if (!Read(a_address + result.size(), chunk, sizeof(chunk))) {
				return {};
			}
			for (const char c : chunk) {
				if (c == '\0') {
					return result;
				}
				const auto byte = static_cast<unsigned char>(c);
				if (byte < 0x20 || byte == 0x7F) {
					return {};
				}
				result += c;
				if (result.size() >= a_max) {
					break;
				}
			}
		}
		return result;
	}

	std::string FixedString(std::uintptr_t a_address, bool* a_ok)
	{
		if (a_ok) {
			*a_ok = false;
		}
		std::uintptr_t entry = 0;
		if (!Read(a_address, entry)) {
			return {};
		}
		if (entry == 0) {
			if (a_ok) {
				*a_ok = true;
			}
			return {};
		}
		// BSStringPool::Entry: +0x08 length (or, for external entries, the entry holding the
		// text), +0x14 flags (bit 1 = external), text right after the 0x18-byte header.
		for (int hop = 0; hop < 4; ++hop) {
			std::uint8_t flags = 0;
			if (!Read(entry + 0x14, flags)) {
				return {};
			}
			if ((flags & 0x02) == 0) {
				break;
			}
			if (!Read(entry + 0x08, entry) || entry == 0) {
				return {};
			}
		}
		std::uint32_t length = 0;
		if (!Read(entry + 0x08, length) || length > 1024) {
			return {};
		}
		std::string text(length, '\0');
		char        terminator = 1;
		if (length && !Read(entry + 0x18, text.data(), length)) {
			return {};
		}
		if (!Read(entry + 0x18 + length, terminator) || terminator != '\0') {
			return {};
		}
		for (const char c : text) {
			const auto byte = static_cast<unsigned char>(c);
			if (byte < 0x20 || byte == 0x7F) {
				return {};
			}
		}
		if (a_ok) {
			*a_ok = true;
		}
		return text;
	}

	std::string TypeName(const void* a_object)
	{
		const auto info = ObjectClass(a_object);
		return info ? info->name : std::string{};
	}

	bool IsA(const void* a_object, std::string_view a_class)
	{
		const auto info = ObjectClass(a_object);
		if (!info) {
			return false;
		}
		return std::ranges::any_of(info->bases, [&](const BaseInfo& a_base) { return a_base.name == a_class; });
	}

	std::optional<std::ptrdiff_t> BaseOffset(const void* a_object, std::string_view a_base)
	{
		const auto info = ObjectClass(a_object);
		if (!info) {
			return std::nullopt;
		}
		for (const auto& base : info->bases) {
			if (base.name != a_base || base.offset < 0) {
				continue;
			}
			if (base.offset == 0) {
				return base.offset;  // shares the object's own vtable
			}
			// A polymorphic base starts with its own vtable, whose locator names the same offset.
			std::uintptr_t vtable = 0;
			if (Read(Addr(a_object) + base.offset, vtable) && InImage(vtable)) {
				const auto& sub = DescribeCached(vtable);
				if (sub.valid && sub.vtableOffset == static_cast<std::uint32_t>(base.offset)) {
					return base.offset;
				}
			}
			return std::nullopt;
		}
		return std::nullopt;
	}

	std::vector<std::ptrdiff_t> MemberOffsets(const void* a_object, std::size_t a_size, std::string_view a_class)
	{
		std::vector<std::ptrdiff_t> found;
		for (std::size_t offset = sizeof(void*); offset + sizeof(void*) <= a_size; offset += sizeof(void*)) {
			std::uintptr_t vtable = 0;
			if (!Read(Addr(a_object) + offset, vtable) || !InImage(vtable)) {
				continue;
			}
			const auto& info = DescribeCached(vtable);
			if (info.valid && info.vtableOffset == 0 && info.name == a_class) {
				found.push_back(static_cast<std::ptrdiff_t>(offset));
			}
		}
		return found;
	}
}
