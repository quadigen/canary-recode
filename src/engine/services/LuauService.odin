package services
// wire:service


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


Luau_Diagnostic :: struct {
	ok:      bool,
	line:    int,
	message: string,
}


luau_service_parse_error :: proc(raw: string) -> (line: int, message: string) {
	rest := raw

	for {
		colon := strings.index_byte(rest, ':')

		if colon < 0 {
			break
		}

		after := rest[colon + 1:]
		end := 0

		for end < len(after) && after[end] >= '0' && after[end] <= '9' {
			end += 1
		}

		if end > 0 && end < len(after) && after[end] == ':' {
			value := 0

			for i in 0 ..< end {
				value = value * 10 + int(after[i] - '0')
			}

			return value, after[end + 1:]
		}

		rest = after
	}

	return 0, raw
}


luau_service_diagnose :: proc(source: string) -> Luau_Diagnostic {
	c_source := strings.clone_to_cstring(source)
	defer delete(c_source)

	out_size: uintptr
	options := luauh.lua_CompileOptions{}

	bytecode := luauh.luau_compile(c_source, uintptr(len(source)), &options, &out_size)

	if bytecode == nil {
		return Luau_Diagnostic {
			ok = false,
			line = 0,
			message = strings.clone("Luau compiler failed"),
		}
	}

	defer luauh.luau_free(cast(rawptr)bytecode)

	state := luauh.luaL_newstate()

	if state == nil {
		return Luau_Diagnostic {
			ok = false,
			line = 0,
			message = strings.clone("Could not create Luau state"),
		}
	}

	defer luauh.lua_close(state)

	status := luauh.luau_load(state, "Script", bytecode, out_size, 0)

	if status == 0 {
		return Luau_Diagnostic{ok = true}
	}

	size: uintptr
	ptr := luauh.lua_tolstring(state, -1, &size)

	if ptr == nil {
		return Luau_Diagnostic {
			ok = false,
			line = 0,
			message = strings.clone("Unknown syntax error"),
		}
	}

	line, message := luau_service_parse_error(strings.string_from_ptr(cast(^u8)ptr, int(size)))

	return Luau_Diagnostic {
		ok = false,
		line = line,
		message = strings.clone(strings.trim_space(message)),
	}
}


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
	case "Tokenize", "TypeCheck", "GetExportedTypes", "GetLintRules":
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
	case "TypeCheck", "GetExportedTypes":
		when luauh.TYPECHECK_AVAILABLE {
			source := vm.ArgString(L, 2)
			c_source := strings.clone_to_cstring(source)
			defer delete(c_source)
			count := method == "TypeCheck" ? luauh.luau_typecheck(L, c_source, uintptr(len(source)), 3) :
				luauh.luau_exported_types(L, c_source, uintptr(len(source)))
			if count == 1 {
				return 1, true
			}
		}
		vm.PushNil(L)
		return 1, true

	case "GetLintRules":
		when luauh.TYPECHECK_AVAILABLE {
			return luauh.luau_lint_rules(L), true
		} else {
			vm.PushNil(L)
			return 1, true
		}

	case "Diagnose":
		source := vm.ArgString(L, 2)

		diagnostic := luau_service_diagnose(source)
		if diagnostic.ok {
			c_source := strings.clone_to_cstring(source)
			line: u32
			message := luauh.luau_diagnose_calls(L, c_source, uintptr(len(source)), &line)
			delete(c_source)
			if message != nil {
				diagnostic = Luau_Diagnostic {
					ok      = false,
					line    = int(line),
					message = strings.clone(string(message)),
				}
				luauh.luau_free(cast(rawptr)message)
			}
		}

		vm.NewTable(L, 0, 3)
		vm.PushBoolean(L, diagnostic.ok)
		vm.SetField(L, -2, "Ok")
		vm.PushNumber(L, f64(diagnostic.line))
		vm.SetField(L, -2, "Line")
		vm.PushString(L, diagnostic.message)
		vm.SetField(L, -2, "Message")

		if diagnostic.message != "" {
			delete(diagnostic.message)
		}

		return 1, true

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
