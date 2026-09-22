package luauh

when ODIN_OS == .JS {
	foreign import lib "../../../../build/web-native/lib/kine_luau_web.o"
} else when ODIN_OS == .Windows {
	foreign import lib {
		"../../../../vendor/build/lib/kine_luau.lib",
		"../../../../vendor/build/vendor/luau/Luau.Compiler.lib",
		"../../../../vendor/build/vendor/luau/Luau.VM.lib",
		"../../../../vendor/build/vendor/luau/Luau.Ast.lib",
		"../../../../vendor/build/vendor/luau/Luau.Bytecode.lib",
		"../../../../vendor/build/vendor/luau/Luau.Common.lib",
	}
} else when #config(KINE_ANDROID, false) {
	foreign import lib {
		"../../../../build/android-native/lib/libkine_luau.a",
		"../../../../build/android-native/luau/libLuau.Compiler.a",
		"../../../../build/android-native/luau/libLuau.VM.a",
		"../../../../build/android-native/luau/libLuau.Ast.a",
		"../../../../build/android-native/luau/libLuau.Bytecode.a",
		"../../../../build/android-native/luau/libLuau.Common.a",
	}
} else {
	foreign import lib {
		"../../../../vendor/build/lib/kine_luau.a",
		"../../../../vendor/build/vendor/luau/libLuau.Compiler.a",
		"../../../../vendor/build/vendor/luau/libLuau.VM.a",
		"../../../../vendor/build/vendor/luau/libLuau.Ast.a",
		"../../../../vendor/build/vendor/luau/libLuau.Bytecode.a",
		"../../../../vendor/build/vendor/luau/libLuau.Common.a",
	}
}

// Mirrors Luau::Lexeme::Type from vendor/luau/Ast/include/Luau/Lexer.h.
Kine_Lexeme :: enum {
	Eof = 0,

	Char_END = 256,

	Equal,
	LessEqual,
	GreaterEqual,
	NotEqual,
	Dot2,
	Dot3,
	SkinnyArrow,
	DoubleColon,
	FloorDiv,

	InterpStringBegin,
	InterpStringMid,
	InterpStringEnd,
	InterpStringSimple,

	AddAssign,
	SubAssign,
	MulAssign,
	DivAssign,
	FloorDivAssign,
	ModAssign,
	PowAssign,
	ConcatAssign,

	RawString,
	QuotedString,
	Number,
	Name,

	Comment,
	BlockComment,

	Attribute,
	AttributeOpen,

	BrokenString,
	BrokenComment,
	BrokenUnicode,
	BrokenInterpDoubleBrace,
	Error,

	Reserved_And,
	Reserved_Break,
	Reserved_Do,
	Reserved_Else,
	Reserved_Elseif,
	Reserved_End,
	Reserved_False,
	Reserved_For,
	Reserved_Function,
	Reserved_If,
	Reserved_In,
	Reserved_Local,
	Reserved_Nil,
	Reserved_Not,
	Reserved_Or,
	Reserved_Repeat,
	Reserved_Return,
	Reserved_Then,
	Reserved_True,
	Reserved_Until,
	Reserved_While,
}

kine_luau_Token :: struct {
	type:  i32,
	begin: u32,
	end:   u32,
}

@(default_calling_convention = "c", link_prefix = "kine_")
foreign lib {
	luau_lexer_create  :: proc(text: cstring, size: uintptr) -> rawptr ---
	luau_lexer_destroy :: proc(handle: rawptr) ---
	luau_lexer_next    :: proc(handle: rawptr) -> kine_luau_Token ---
}