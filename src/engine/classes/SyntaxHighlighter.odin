package classes

import "core:strings"

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import luauh "../vm/luauh"

SyntaxHighlighter_Class := Class_Info {
	name   = "SyntaxHighlighter",
	parent = &Instance_Class,
}

Syntax_Highlighting_Language :: enum {
	None,
	Luau,
}

Syntax_Rule_Kind :: enum {
	Keyword,
	Prefix,
	Range,
	Regex,
}

Syntax_Span :: struct {
	start:  int,
	finish: int,
	color3: datatypes.Color3,
}

Syntax_Rule :: struct {
	kind:           Syntax_Rule_Kind,
	head:           string,
	tail:           string,
	color3:         datatypes.Color3,
	program:        ^Regex_Program,
	program_loaded: bool,
}

SyntaxHighlighter :: struct {
	using object: Object,

	enabled: bool,
	language:  Syntax_Highlighting_Language,

	rules:         [dynamic]Syntax_Rule,
	rules_version: int,

	cached_text:           string,
	cached_rules_version:  int,
	spans:                 [dynamic]Syntax_Span,
	spans_valid:           bool,
}

SyntaxHighlighter_Init :: proc() -> SyntaxHighlighter {
	return SyntaxHighlighter {
		object              = Object_Init(&SyntaxHighlighter_Class, "SyntaxHighlighter"),
		enabled             = true,
		language            = .Luau,
		cached_rules_version = -1,
		spans_valid         = false,
	}
}

SyntaxHighlighter_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	highlighter := new(SyntaxHighlighter)
	highlighter^ = SyntaxHighlighter_Init()
	return &highlighter.object
}

syntax_rule_destroy :: proc(rule: ^Syntax_Rule) {
	if rule == nil {
		return
	}

	if len(rule.head) > 0 {
		delete(rule.head)
		rule.head = ""
	}

	if len(rule.tail) > 0 {
		delete(rule.tail)
		rule.tail = ""
	}

	if rule.program != nil {
		regex_program_destroy(rule.program)
		rule.program = nil
	}

	rule.program_loaded = false
}

syntax_highlighter_clear_rules :: proc(highlighter: ^SyntaxHighlighter) {
	if highlighter == nil {
		return
	}

	for &rule in highlighter.rules {
		syntax_rule_destroy(&rule)
	}

	clear(&highlighter.rules)
	highlighter.rules_version += 1
	highlighter.cached_rules_version = -1
	highlighter.spans_valid = false
}

SyntaxHighlighter_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	highlighter := cast(^SyntaxHighlighter)object

	syntax_highlighter_clear_rules(highlighter)

	if highlighter.spans != nil {
		delete(highlighter.spans)
		highlighter.spans = nil
	}

	if len(highlighter.cached_text) > 0 {
		delete(highlighter.cached_text)
		highlighter.cached_text = ""
	}

	Object_Destroy(object)
	free(highlighter)
}

SyntaxHighlighter_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^SyntaxHighlighter)source
	dst := cast(^SyntaxHighlighter)destination

	dst.enabled = src.enabled
	dst.language = src.language

	for rule in src.rules {
		copy := Syntax_Rule {
			kind   = rule.kind,
			head   = strings.clone(rule.head),
			tail   = strings.clone(rule.tail),
			color3 = rule.color3,
		}

		append(&dst.rules, copy)
	}

	dst.rules_version = src.rules_version + 1
	dst.cached_rules_version = -1
	dst.spans_valid = false
}

syntax_highlighter_add_rule :: proc(
	highlighter: ^SyntaxHighlighter,
	kind_name: string,
	color3: datatypes.Color3,
	pattern: string,
	tail: string,
) {
	if highlighter == nil || len(pattern) == 0 {
		return
	}

	rule := Syntax_Rule {
		head   = strings.clone(pattern),
		tail   = strings.clone(tail),
		color3 = color3,
	}

	switch kind_name {
	case "Keyword":
		rule.kind = .Keyword
	case "Prefix":
		rule.kind = .Prefix
	case "Range":
		rule.kind = .Range
	case "Regex":
		rule.kind = .Regex
		rule.head = strings.clone(pattern)
	case:
		syntax_rule_destroy(&rule)
		return
	}

	append(&highlighter.rules, rule)
	highlighter.rules_version += 1
	highlighter.spans_valid = false
}

syntax_highlighter_add_keyword :: proc(
	highlighter: ^SyntaxHighlighter,
	word: string,
	color3: datatypes.Color3,
) {
	if highlighter == nil || len(word) == 0 {
		return
	}

	append(
		&highlighter.rules,
		Syntax_Rule {
			kind   = .Keyword,
			head   = strings.clone(word),
			color3 = color3,
		},
	)

	highlighter.rules_version += 1
	highlighter.spans_valid = false
}

syntax_highlighter_add_regex :: proc(
	highlighter: ^SyntaxHighlighter,
	color3: datatypes.Color3,
	pattern: string,
) {
	if highlighter == nil || len(pattern) == 0 {
		return
	}

	append(
		&highlighter.rules,
		Syntax_Rule {
			kind   = .Regex,
			head   = strings.clone(pattern),
			color3 = color3,
		},
	)

	highlighter.rules_version += 1
	highlighter.spans_valid = false
}

SyntaxHighlighter_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	highlighter := cast(^SyntaxHighlighter)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, highlighter.enabled)
		return true

	case "Language":
		switch highlighter.language {
		case .Luau:
			vm.PushString(L, "Luau")
		case .None:
			vm.PushString(L, "None")
		}
		return true

	case "RuleCount":
		vm.PushNumber(L, f64(len(highlighter.rules)))
		return true

	case "Rules":
		if datatype_registry == nil {
			return false
		}

		vm.NewTable(L, len(highlighter.rules), 0)

		for rule, index in highlighter.rules {
			vm.NewTable(L, 0, 5)

			vm.PushString(L, syntax_rule_kind_name(rule.kind))
			vm.SetField(L, -2, "Kind")

			vm.PushString(L, rule.head)
			vm.SetField(L, -2, "Pattern")

			datatypes.Push_Color3(L, datatype_registry, rule.color3)
			vm.SetField(L, -2, "Color3")

			if rule.kind == .Range {
				vm.PushString(L, rule.tail)
				vm.SetField(L, -2, "EndPattern")
			}

			vm.SetArrayValue(L, -2, index + 1)
		}

		return true
	}

	return false
}

syntax_rule_kind_name :: proc(kind: Syntax_Rule_Kind) -> string {
	switch kind {
	case .Keyword:
		return "Keyword"
	case .Prefix:
		return "Prefix"
	case .Range:
		return "Range"
	case .Regex:
		return "Regex"
	}

	return "Keyword"
}

SyntaxHighlighter_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	highlighter := cast(^SyntaxHighlighter)object

	switch key {
	case "Enabled":
		highlighter.enabled = vm.ArgBoolean(L, value_index)
		highlighter.spans_valid = false
		return true

	case "Language":
		value := vm.ArgString(L, value_index)

		switch value {
		case "Luau":
			highlighter.language = .Luau
		case "None":
			highlighter.language = .None
		}

		highlighter.spans_valid = false
		return true
	}

	return false
}

SyntaxHighlighter_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	highlighter := cast(^SyntaxHighlighter)object

	switch method {
	case "AddRule":
		if datatype_registry == nil {
			return 0, true
		}

		kind_name := vm.ArgString(L, 2)
		color3 := datatypes.Arg_Color3(L, 3, datatype_registry)
		pattern := vm.ArgString(L, 4)

		tail: string
		if !vm.IsNoneOrNil(L, 5) {
			tail = vm.ArgString(L, 5)
		}

		syntax_highlighter_add_rule(
			highlighter,
			kind_name,
			color3,
			pattern,
			tail,
		)

		return 0, true

	case "AddKeyword":
		if datatype_registry == nil {
			return 0, true
		}

		color3 := datatypes.Arg_Color3(L, 2, datatype_registry)
		top := vm.StackTop(L)

		for index in 3 ..= top {
			syntax_highlighter_add_keyword(
				highlighter,
				vm.ArgString(L, index),
				color3,
			)
		}

		return 0, true

	case "AddRegex":
		if datatype_registry == nil {
			return 0, true
		}

		color3 := datatypes.Arg_Color3(L, 2, datatype_registry)
		pattern := vm.ArgString(L, 3)

		syntax_highlighter_add_regex(
			highlighter,
			color3,
			pattern,
		)

		return 0, true

	case "ClearRules":
		syntax_highlighter_clear_rules(highlighter)
		return 0, true
	}

	return 0, false
}

Register_SyntaxHighlighter :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&SyntaxHighlighter_Class,

		SyntaxHighlighter_construct,
		SyntaxHighlighter_destroy,

		get =
			SyntaxHighlighter_get,

		set =
			SyntaxHighlighter_set,

		namecall =
			SyntaxHighlighter_namecall,

		clone =
			SyntaxHighlighter_clone,

		properties = []string{
			"Enabled",
			"Language",
			"Rules",
			"RuleCount",

			"AddRule",
			"AddKeyword",
			"AddRegex",
			"ClearRules",
		},
	)
}

syntax_highlighter_for_box :: proc(box: ^TextBox) -> ^SyntaxHighlighter {
	if box == nil {
		return nil
	}

	child := Find_First_Child_Of_Class(
		cast(^Object)box,
		"SyntaxHighlighter",
	)

	if child == nil {
		return nil
	}

	return cast(^SyntaxHighlighter)child
}

syntax_is_word_byte :: proc(value: u8) -> bool {
	return (value >= 'a' && value <= 'z') ||
	       (value >= 'A' && value <= 'Z') ||
	       (value >= '0' && value <= '9') ||
	       value == '_'
}

syntax_rule_match :: proc(
	rule: ^Syntax_Rule,
	text: string,
	position: int,
	line_end: int,
) -> int {
	if rule == nil {
		return -1
	}

	switch rule.kind {
	case .Keyword:
		if len(rule.head) == 0 {
			return -1
		}

		if position > 0 &&
		   syntax_is_word_byte(text[position - 1]) {
			return -1
		}

		if !strings.has_prefix(text[position:], rule.head) {
			return -1
		}

		end := position + len(rule.head)

		if end > line_end {
			return -1
		}

		if end < len(text) &&
		   syntax_is_word_byte(text[end]) {
			return -1
		}

		return end

	case .Prefix:
		if len(rule.head) == 0 {
			return -1
		}

		if !strings.has_prefix(text[position:], rule.head) {
			return -1
		}

		return line_end

	case .Range:
		if len(rule.head) == 0 {
			return -1
		}

		if !strings.has_prefix(text[position:], rule.head) {
			return -1
		}

		body_start := position + len(rule.head)

		if len(rule.tail) == 0 {
			return line_end
		}

		found := strings.index(text[body_start:], rule.tail)

		if found < 0 {
			return len(text)
		}

		return body_start + found + len(rule.tail)

	case .Regex:
		syntax_rule_ensure_program(rule)

		if rule.program == nil {
			return -1
		}

		end := regex_match_program(
			rule.program,
			text,
			position,
			line_end,
		)

		if end < position {
			return -1
		}

		return end
	}

	return -1
}

syntax_rule_ensure_program :: proc(rule: ^Syntax_Rule) {
	if rule == nil || rule.program_loaded {
		return
	}

	rule.program = regex_compile(rule.head)
	rule.program_loaded = true
}

syntax_highlighter_ensure :: proc(
	highlighter: ^SyntaxHighlighter,
	text: string,
) {
	if highlighter == nil {
		return
	}

	if highlighter.spans_valid &&
	   highlighter.cached_rules_version == highlighter.rules_version &&
	   strings.compare(highlighter.cached_text, text) == 0 {
		return
	}

	if len(highlighter.cached_text) > 0 {
		delete(highlighter.cached_text)
	}

	highlighter.cached_text = strings.clone(text)

	if highlighter.spans != nil {
		delete(highlighter.spans)
	}

	highlighter.spans = nil
	highlighter.spans_valid = false

	if !highlighter.enabled {
		highlighter.spans_valid = true
		highlighter.cached_rules_version = highlighter.rules_version
		return
	}

	switch highlighter.language {
	case .Luau:
		syntax_highlighter_luau_spans(highlighter, text)
	case .None:
		syntax_highlighter_rule_spans(highlighter, text)
	}

	highlighter.spans_valid = true
	highlighter.cached_rules_version = highlighter.rules_version
}

syntax_highlighter_rule_spans :: proc(
	highlighter: ^SyntaxHighlighter,
	text: string,
) {
	if highlighter == nil {
		return
	}

	if len(highlighter.rules) == 0 {
		return
	}

	position := 0

	for position < len(text) {
		line_end := position

		for line_end < len(text) &&
		      text[line_end] != '\n' {
			line_end += 1
		}

		matched := false

		for &rule in highlighter.rules {
			end := syntax_rule_match(
				&rule,
				text,
				position,
				line_end,
			)

			if end > position {
				append(
					&highlighter.spans,
					Syntax_Span {
						start  = position,
						finish = end,
						color3 = rule.color3,
					},
				)

				position = end
				matched = true
				break
			}
		}

		if !matched {
			position += 1
		}
	}
}

syntax_luau_span_color :: proc(type: i32) -> (datatypes.Color3, bool) {
	if type >= i32(luauh.Kine_Lexeme.Reserved_And) &&
	   type <= i32(luauh.Kine_Lexeme.Reserved_While) {
		return datatypes.Color3{0.05, 0.42, 0.90}, true
	}

	#partial switch luauh.Kine_Lexeme(type) {
	case .QuotedString,
	     .RawString,
	     .InterpStringBegin,
	     .InterpStringMid,
	     .InterpStringEnd,
	     .InterpStringSimple:
		return datatypes.Color3{0.10, 0.65, 0.28}, true

	case .Number:
		return datatypes.Color3{0.85, 0.40, 0.12}, true

	case .Comment, .BlockComment:
		return datatypes.Color3{0.40, 0.45, 0.50}, true

	case .Attribute, .AttributeOpen:
		return datatypes.Color3{0.60, 0.35, 0.75}, true
	}

	return {}, false
}

syntax_highlighter_luau_spans :: proc(
	highlighter: ^SyntaxHighlighter,
	text: string,
) {
	if highlighter == nil || len(text) == 0 {
		return
	}

	c_text := strings.clone_to_cstring(text)
	defer delete(c_text)

	handle := luauh.luau_lexer_create(c_text, uintptr(len(text)))

	if handle == nil {
		return
	}

	defer luauh.luau_lexer_destroy(handle)

	for {
		token := luauh.luau_lexer_next(handle)

		if token.type == i32(luauh.Kine_Lexeme.Eof) {
			break
		}

		start := int(token.begin)
		finish := int(token.end)

		if finish <= start {
			continue
		}

		color, colored := syntax_luau_span_color(token.type)

		if !colored {
			continue
		}

		append(
			&highlighter.spans,
			Syntax_Span {
				start  = start,
				finish = finish,
				color3 = color,
			},
		)
	}
}

// ---------------------------------------------------------------------------
// Regex subset engine
//
// Supported syntax:
//   literal characters (escape with \), ., [...]/[^...]/[a-z] classes,
//   \d \w \s (and the negated forms), groups (...), alternation |, and the
//   quantifiers * + ?. Matching is always anchored at the scanned position
//   and bounded to the current line.
// ---------------------------------------------------------------------------

Regex_Op :: enum {
	Empty,
	Char,
	Any,
	Class,
	Group,
	Alternation,
}

Regex_Node :: struct {
	op:         Regex_Op,
	ch:         u8,
	negate:     bool,
	class_bits: [4]u64,
	values:     [dynamic]Regex_Node,
	branches:   [dynamic][dynamic]Regex_Node,
	min:        int,
	max:        int,
}

Regex_Program :: struct {
	nodes: [dynamic]Regex_Node,
}

regex_class_add :: proc(bits: ^[4]u64, value: u8) {
	bits[value >> 6] |= (u64(1) << uint(value & 63))
}

regex_class_has :: proc(bits: [4]u64, value: u8) -> bool {
	return (bits[value >> 6] >> uint(value & 63)) & 1 == 1
}

regex_fill_digits :: proc(bits: ^[4]u64) {
	for value in '0' ..= '9' {
		regex_class_add(bits, u8(value))
	}
}

regex_fill_letters :: proc(bits: ^[4]u64) {
	for value in 'a' ..= 'z' {
		regex_class_add(bits, u8(value))
	}
	for value in 'A' ..= 'Z' {
		regex_class_add(bits, u8(value))
	}
}

regex_fill_whitespace :: proc(bits: ^[4]u64) {
	regex_class_add(bits, u8(0x20))
	regex_class_add(bits, u8(0x09))
	regex_class_add(bits, u8(0x0A))
	regex_class_add(bits, u8(0x0D))
	regex_class_add(bits, u8(0x0B))
	regex_class_add(bits, u8(0x0C))
}

regex_nodes_destroy :: proc(nodes: []Regex_Node) {
	for &node in nodes {
		#partial switch node.op {
		case .Group:
			regex_nodes_destroy(node.values[:])
			delete(node.values)
			node.values = nil
		case .Alternation:
			for branch in node.branches {
				regex_nodes_destroy(branch[:])
				delete(branch)
			}
			delete(node.branches)
			node.branches = nil
		case:
		}
	}
}

regex_branches_destroy :: proc(branches: [dynamic][dynamic]Regex_Node) {
	for branch in branches {
		regex_nodes_destroy(branch[:])
		delete(branch)
	}

	delete(branches)
}

regex_program_destroy :: proc(program: ^Regex_Program) {
	if program == nil {
		return
	}

	regex_nodes_destroy(program.nodes[:])
	delete(program.nodes)
	program.nodes = nil
	free(program)
}

regex_compile_class :: proc(pattern: string, pos: ^int) -> (Regex_Node, bool) {
	node := Regex_Node {
		op = .Class,
		min = 1,
		max = 1,
	}

	if pos^ < len(pattern) && pattern[pos^] == '^' {
		node.negate = true
		pos^ += 1
	}

	first := true
	closed := false
	ranges: [dynamic][2]u8
	defer delete(ranges)

	for pos^ < len(pattern) {
		value := pattern[pos^]

		if value == ']' && !first {
			pos^ += 1
			closed = true
			break
		}

		if value == '\\' {
			pos^ += 1

			if pos^ >= len(pattern) {
				return {}, false
			}

			escaped := pattern[pos^]
			pos^ += 1

			switch escaped {
			case 'd':
				append(&ranges, [2]u8{'0', '9'})
			case 'w':
				append(&ranges, [2]u8{'a', 'z'})
				append(&ranges, [2]u8{'A', 'Z'})
				append(&ranges, [2]u8{'0', '9'})
				append(&ranges, [2]u8{'_', '_'})
			case 's':
				append(&ranges, [2]u8{0x09, 0x0D})
				append(&ranges, [2]u8{0x20, 0x20})
			case 'n':
				append(&ranges, [2]u8{0x0A, 0x0A})
			case 't':
				append(&ranges, [2]u8{0x09, 0x09})
			case 'r':
				append(&ranges, [2]u8{0x0D, 0x0D})
			case:
				append(&ranges, [2]u8{escaped, escaped})
			}

			first = false
			continue
		}

		if pos^ + 2 < len(pattern) &&
		   pattern[pos^ + 1] == '-' &&
		   pattern[pos^ + 2] != ']' {
			lo := value
			hi := pattern[pos^ + 2]

			if hi < lo {
				lo, hi = hi, lo
			}

			append(&ranges, [2]u8{lo, hi})
			pos^ += 3
			first = false
			continue
		}

		append(&ranges, [2]u8{value, value})
		pos^ += 1
		first = false
	}

	if !closed {
		return {}, false
	}

	for range_pair in ranges {
		for byte_value in range_pair[0] ..= range_pair[1] {
			regex_class_add(&node.class_bits, byte_value)
		}
	}

	return node, true
}

regex_compile_unit :: proc(pattern: string, pos: ^int) -> (Regex_Node, bool) {
	if pos^ >= len(pattern) {
		return {}, false
	}

	value := pattern[pos^]
	node: Regex_Node
	ok := false

	switch value {
	case '(':
		pos^ += 1

		branches, branch_ok := regex_compile_alternation(
			pattern,
			pos,
			')',
		)

		if !branch_ok {
			return {}, false
		}

		if len(branches) > 1 {
			node = Regex_Node {
				op       = .Alternation,
				min      = 1,
				max      = 1,
				branches = branches,
			}
		} else {
			branch := branches[0]
			delete(branches)

			node = Regex_Node {
				op     = .Group,
				min    = 1,
				max    = 1,
				values = branch,
			}
		}

		ok = true

	case '[':
		pos^ += 1
		node, ok = regex_compile_class(pattern, pos)

	case '\\':
		pos^ += 1

		if pos^ >= len(pattern) {
			return {}, false
		}

		escaped := pattern[pos^]
		pos^ += 1

		switch escaped {
		case 'd':
			node = Regex_Node {
				op         = .Class,
				min        = 1,
				max        = 1,
			}
			regex_fill_digits(&node.class_bits)
		case 'D':
			node = Regex_Node {
				op         = .Class,
				negate     = true,
				min        = 1,
				max        = 1,
			}
			regex_fill_digits(&node.class_bits)
		case 'w':
			node = Regex_Node {
				op         = .Class,
				min        = 1,
				max        = 1,
			}
			regex_fill_letters(&node.class_bits)
			regex_fill_digits(&node.class_bits)
			regex_class_add(&node.class_bits, '_')
		case 'W':
			node = Regex_Node {
				op         = .Class,
				negate     = true,
				min        = 1,
				max        = 1,
			}
			regex_fill_letters(&node.class_bits)
			regex_fill_digits(&node.class_bits)
			regex_class_add(&node.class_bits, '_')
		case 's':
			node = Regex_Node {
				op         = .Class,
				min        = 1,
				max        = 1,
			}
			regex_fill_whitespace(&node.class_bits)
		case 'S':
			node = Regex_Node {
				op         = .Class,
				negate     = true,
				min        = 1,
				max        = 1,
			}
			regex_fill_whitespace(&node.class_bits)
		case 'n':
			node = Regex_Node {
				op  = .Char,
				ch  = 0x0A,
				min = 1,
				max = 1,
			}
		case 't':
			node = Regex_Node {
				op  = .Char,
				ch  = 0x09,
				min = 1,
				max = 1,
			}
		case 'r':
			node = Regex_Node {
				op  = .Char,
				ch  = 0x0D,
				min = 1,
				max = 1,
			}
		case:
			node = Regex_Node {
				op  = .Char,
				ch  = escaped,
				min = 1,
				max = 1,
			}
		}

		ok = true

	case '.':
		pos^ += 1

		node = Regex_Node {
			op  = .Any,
			min = 1,
			max = 1,
		}

		ok = true

	case '*', '+', '?', ')', '|', ']':
		return {}, false

	case:
		pos^ += 1

		node = Regex_Node {
			op  = .Char,
			ch  = value,
			min = 1,
			max = 1,
		}

		ok = true
	}

	if !ok {
		return {}, false
	}

	if pos^ < len(pattern) {
		quantifier := pattern[pos^]

		switch quantifier {
		case '*':
			pos^ += 1
			node.min = 0
			node.max = -1
		case '+':
			pos^ += 1
			node.min = 1
			node.max = -1
		case '?':
			pos^ += 1
			node.min = 0
			node.max = 1
		case:
		}
	}

	return node, true
}

regex_compile_alternation :: proc(
	pattern: string,
	pos: ^int,
	stop: u8,
) -> ([dynamic][dynamic]Regex_Node, bool) {
	current: [dynamic]Regex_Node
	branches: [dynamic][dynamic]Regex_Node

	for pos^ < len(pattern) {
		value := pattern[pos^]

		if value == ')' && stop != 0 {
			pos^ += 1
			append(&branches, current)
			return branches, true
		}

		if value == ')' {
			regex_nodes_destroy(current[:])
			delete(current)
			regex_branches_destroy(branches)
			return nil, false
		}

		if value == '|' {
			pos^ += 1
			append(&branches, current)
			current = nil
			continue
		}

		node, ok := regex_compile_unit(pattern, pos)

		if !ok {
			regex_nodes_destroy(current[:])
			delete(current)
			regex_branches_destroy(branches)
			return nil, false
		}

		append(&current, node)
	}

	if stop != 0 {
		regex_nodes_destroy(current[:])
		delete(current)
		regex_branches_destroy(branches)
		return nil, false
	}

	append(&branches, current)
	return branches, true
}

regex_compile :: proc(pattern: string) -> ^Regex_Program {
	program := new(Regex_Program)

	pos := 0
	branches, ok := regex_compile_alternation(pattern, &pos, 0)

	if !ok {
		return program
	}

	if len(branches) == 1 {
		program.nodes = branches[0]
		delete(branches)
	} else if len(branches) > 1 {
		append(
			&program.nodes,
			Regex_Node {
				op       = .Alternation,
				min      = 1,
				max      = 1,
				branches = branches,
			},
		)
	}

	return program
}

regex_match_once :: proc(
	node: Regex_Node,
	text: string,
	position: int,
	bound: int,
) -> int {
	switch node.op {
	case .Char:
		if position < bound &&
		   text[position] == node.ch {
			return position + 1
		}

		return -1

	case .Any:
		if position < bound &&
		   text[position] != '\n' {
			return position + 1
		}

		return -1

	case .Class:
		if position >= bound {
			return -1
		}

		value := text[position]
		hit := regex_class_has(node.class_bits, value)

		if hit == !node.negate {
			return position + 1
		}

		return -1

	case .Group:
		return regex_match_seq(
			node.values[:],
			text,
			position,
			bound,
		)

	case .Alternation:
		for branch in node.branches {
			end := regex_match_seq(
				branch[:],
				text,
				position,
				bound,
			)

			if end >= 0 {
				return end
			}
		}

		return -1

	case .Empty:
		return position
	}

	return -1
}

regex_node_ends :: proc(
	node: Regex_Node,
	text: string,
	position: int,
	bound: int,
) -> [dynamic]int {
	ends: [dynamic]int

	if node.op == .Empty {
		append(&ends, position)
		return ends
	}

	current := position
	repetitions := 0

	for repetitions <= bound - position {
		if repetitions >= node.min &&
		   (node.max < 0 || repetitions <= node.max) {
			append(&ends, current)
		}

		if node.max >= 0 &&
		   repetitions >= node.max {
			break
		}

		next := regex_match_once(
			node,
			text,
			current,
			bound,
		)

		if next < 0 {
			break
		}

		if next == current {
			break
		}

		if next > bound {
			break
		}

		current = next
		repetitions += 1
	}

	return ends
}

regex_match_suffix :: proc(
	nodes: []Regex_Node,
	index: int,
	text: string,
	position: int,
	bound: int,
) -> int {
	if index >= len(nodes) {
		return position
	}

	node := nodes[index]
	ends := regex_node_ends(node, text, position, bound)
	defer delete(ends)

	for end_index := len(ends) - 1; end_index >= 0; end_index -= 1 {
		result := regex_match_suffix(
			nodes,
			index + 1,
			text,
			ends[end_index],
			bound,
		)

		if result >= 0 {
			return result
		}
	}

	return -1
}

regex_match_seq :: proc(
	nodes: []Regex_Node,
	text: string,
	position: int,
	bound: int,
) -> int {
	if len(nodes) == 0 {
		return position
	}

	return regex_match_suffix(
		nodes,
		0,
		text,
		position,
		bound,
	)
}

regex_match_program :: proc(
	program: ^Regex_Program,
	text: string,
	position: int,
	bound: int,
) -> int {
	if program == nil {
		return -1
	}

	return regex_match_seq(
		program.nodes[:],
		text,
		position,
		bound,
	)
}