package services

// wire:service global="LuauService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import luauh "../vm/luauh"


LuauService_Class := classes.Class_Info {
	name   = "LuauService",
	parent = &Service_Class,
}

LuauService :: struct {
	using service: Service,
}

luau_service_token_class :: proc(type: i32) -> string {
	if type >= i32(luauh.Kine_Lexeme.Reserved_And) &&
	   type <= i32(luauh.Kine_Lexeme.Reserved_While) {
		return "Keyword"
	}

	#partial switch luauh.Kine_Lexeme(type) {
	case .QuotedString,
	     .RawString,
	     .InterpStringBegin,
	     .InterpStringMid,
	     .InterpStringEnd,
	     .InterpStringSimple,
	     .BrokenString:
		return "String"

	case .Number:
		return "Number"

	case .Name:
		return "Identifier"

	case .Comment, .BlockComment, .BrokenComment:
		return "Comment"

	case .Attribute, .AttributeOpen:
		return "Attribute"

	case .BrokenUnicode, .BrokenInterpDoubleBrace, .Error:
		return "Broken"

	case:
		return "Symbol"
	}

	return "Symbol"
}

luau_service_tokenize :: proc(source: string) -> [dynamic]luauh.kine_luau_Token {
	tokens: [dynamic]luauh.kine_luau_Token

	if len(source) == 0 {
		return tokens
	}

	c_source := strings.clone_to_cstring(source)
	defer delete(c_source)

	handle := luauh.luau_lexer_create(c_source, uintptr(len(source)))

	if handle == nil {
		return tokens
	}

	defer luauh.luau_lexer_destroy(handle)

	for {
		token := luauh.luau_lexer_next(handle)

		if token.type == i32(luauh.Kine_Lexeme.Eof) {
			break
		}

		append(&tokens, token)
	}

	return tokens
}


// -----------------------------------------------------------------------------
// Luau API
// -----------------------------------------------------------------------------

luau_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	_ = object
	_ = datatype_registry
	_ = enum_registry

	switch key {
	case "Tokenize":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}


luau_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	_ = object
	_ = datatype_registry
	_ = enum_registry

	switch method {
	case "Tokenize":
		source := vm.ArgString(L, 2)

		tokens := luau_service_tokenize(source)
		defer delete(tokens)

		vm.NewTable(L, len(tokens), 0)

		for token, index in tokens {
			vm.NewTable(L, 0, 4)

			vm.PushString(L, luau_service_token_class(token.type))
			vm.SetField(L, -2, "Type")

			vm.PushNumber(L, f64(token.begin) + 1)
			vm.SetField(L, -2, "Start")

			vm.PushNumber(L, f64(token.end))
			vm.SetField(L, -2, "Finish")

			vm.PushString(L, source[token.begin:token.end])
			vm.SetField(L, -2, "Text")

			vm.SetArrayValue(L, -2, index + 1)
		}

		return 1, true
	}

	return 0, false
}


// -----------------------------------------------------------------------------
// Lifecycle
// -----------------------------------------------------------------------------

LuauService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	_ = renderer

	service := new(LuauService)

	service.service = Service_Init(&LuauService_Class, "LuauService", data_model)

	return &service.object
}

LuauService_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	_ = renderer

	service := cast(^LuauService)object

	classes.Object_Destroy(object)
	free(service)
}


Register_LuauService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&LuauService_Class,
		LuauService_construct,
		LuauService_destroy,
		creatable = false,
		get = luau_service_get,
		namecall = luau_service_namecall,
	)
}
