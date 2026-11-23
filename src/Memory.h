#pragma once

// Guarded reads of game memory, and the game's own MSVC run-time type information (RTTI).
//
// The diagnostics read structures whose layout CommonLibSF doesn't have right for every game
// build: OSF found the armor's biped-slot component at ARMO+0x200 on 1.16.244, where
// CommonLibSF's header says 0x230. So instead of trusting header offsets, the reports find
// components through the type information the compiler put in Starfield.exe, read only memory
// that is committed and readable, and say so when something can't be found.
namespace Memory
{
	[[nodiscard]] bool Readable(std::uintptr_t a_address, std::size_t a_size) noexcept;
	[[nodiscard]] bool Read(std::uintptr_t a_address, void* a_out, std::size_t a_size) noexcept;

	template <class T>
	[[nodiscard]] bool Read(std::uintptr_t a_address, T& a_out) noexcept
	{
		return Read(a_address, &a_out, sizeof(T));
	}

	template <class T>
	[[nodiscard]] std::uintptr_t Addr(const T* a_pointer) noexcept
	{
		return reinterpret_cast<std::uintptr_t>(a_pointer);
	}

	// Starfield.exe's image.
	[[nodiscard]] bool InImage(std::uintptr_t a_address) noexcept;

	// Printable ASCII text at a_address, at most a_max characters; "" when unreadable or when
	// it holds anything but printable characters before its terminator.
	[[nodiscard]] std::string CString(std::uintptr_t a_address, std::size_t a_max = 256);

	// The text of the BSFixedString stored at a_address (a pointer to a string-pool entry);
	// "" when empty or unreadable. a_ok is false when the pointer was set but didn't decode.
	[[nodiscard]] std::string FixedString(std::uintptr_t a_address, bool* a_ok = nullptr);

	// The class name of the object at a_object, from its vtable's RTTI ("TESObjectARMA");
	// "" when it has no readable RTTI.
	[[nodiscard]] std::string TypeName(const void* a_object);

	// True when the object's class is a_class or derives from it (names as TypeName gives them).
	[[nodiscard]] bool IsA(const void* a_object, std::string_view a_class);

	// Where base class a_base sits inside the object, from the object's RTTI hierarchy, checked
	// against the vtable found there. Empty when the class doesn't have that base.
	[[nodiscard]] std::optional<std::ptrdiff_t> BaseOffset(const void* a_object, std::string_view a_base);

	// Offsets (from a_object) of polymorphic member objects of exactly class a_class, within
	// the first a_size bytes.
	[[nodiscard]] std::vector<std::ptrdiff_t> MemberOffsets(const void* a_object, std::size_t a_size, std::string_view a_class);
}
