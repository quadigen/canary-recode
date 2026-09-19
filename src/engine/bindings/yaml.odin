package kineffi

import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

import kineffi "../bindings"

Yaml_Document :: struct {
	document: kineffi.yaml_document_t,
	loaded:   bool,
}

Yaml_Error :: struct {
	kind:    kineffi.yaml_error_type_t,
	message: string,
	line:    int,
	column:  int,
}

Yaml_Node :: ^kineffi.yaml_node_t

Yaml_Error_Delete :: proc(err: ^Yaml_Error) {
	if err == nil {
		return
	}

	if len(err.message) > 0 {
		delete(err.message)
		err.message = ""
	}
}

Yaml_Make_Error :: proc(
	parser: ^kineffi.yaml_parser_t,
) -> Yaml_Error {
	result := Yaml_Error{
		kind   = parser.error,
		line   = int(parser.problem_mark.line) + 1,
		column = int(parser.problem_mark.column) + 1,
	}

	if parser.problem != nil {
		message, alloc_err := strings.clone_from_cstring(parser.problem)
		if alloc_err == nil {
			result.message = message
		}
	}

	return result
}

Yaml_Parse_Bytes :: proc(
	data: []u8,
) -> (^Yaml_Document, Yaml_Error) {
	parser: kineffi.yaml_parser_t

	if kineffi.yaml_parser_initialize(&parser) == 0 {
		return nil, Yaml_Error{
			kind    = .MEMORY_ERROR,
			message = "",
		}
	}

	defer kineffi.yaml_parser_delete(&parser)

	input: ^u8 = nil

	if len(data) > 0 {
		input = raw_data(data)
	}

	kineffi.yaml_parser_set_input_string(
		&parser,
		input,
		len(data),
	)

	result, alloc_err := new(Yaml_Document)
	if alloc_err != nil {
		return nil, Yaml_Error{
			kind = .MEMORY_ERROR,
		}
	}

	if kineffi.yaml_parser_load(
		&parser,
		&result.document,
	) == 0 {
		err := Yaml_Make_Error(&parser)
		free(result)
		return nil, err
	}

	result.loaded = true

	return result, {}
}

Yaml_Parse :: proc(
	source: string,
) -> (^Yaml_Document, Yaml_Error) {
	data: []u8

	if len(source) > 0 {
		data = mem.slice_ptr(
			cast(^u8)raw_data(source),
			len(source),
		)
	}

	return Yaml_Parse_Bytes(data)
}

Yaml_Load :: proc(
	path: string,
) -> (^Yaml_Document, Yaml_Error) {
	data, file_err := os.read_entire_file(
		path,
		context.allocator,
	)

	if file_err != nil {
		message, _ := strings.clone("Failed to read YAML file")

		return nil, Yaml_Error{
			message = message,
		}
	}

	defer delete(data)

	return Yaml_Parse_Bytes(data)
}

Yaml_Close :: proc(
	document: ^Yaml_Document,
) {
	if document == nil {
		return
	}

	if document.loaded {
		kineffi.yaml_document_delete(
			&document.document,
		)

		document.loaded = false
	}

	free(document)
}

Yaml_Root :: proc(
	document: ^Yaml_Document,
) -> Yaml_Node {
	if document == nil || !document.loaded {
		return nil
	}

	return kineffi.yaml_document_get_root_node(
		&document.document,
	)
}

Yaml_Type :: proc(
	node: Yaml_Node,
) -> kineffi.yaml_node_type_t {
	if node == nil {
		return .NO_NODE
	}

	return node.type
}

Yaml_Is_Scalar :: proc(node: Yaml_Node) -> bool {
	return node != nil &&
	       node.type == .SCALAR_NODE
}

Yaml_Is_Sequence :: proc(node: Yaml_Node) -> bool {
	return node != nil &&
	       node.type == .SEQUENCE_NODE
}

Yaml_Is_Mapping :: proc(node: Yaml_Node) -> bool {
	return node != nil &&
	       node.type == .MAPPING_NODE
}

Yaml_As_String :: proc(
	node: Yaml_Node,
) -> (string, bool) {
	if !Yaml_Is_Scalar(node) {
		return "", false
	}

	value := node.data.scalar.value
	length := int(node.data.scalar.length)

	if value == nil {
		return "", true
	}

	return strings.string_from_ptr(
		value,
		length,
	), true
}

Yaml_As_Int :: proc(
	node: Yaml_Node,
) -> (int, bool) {
	value, ok := Yaml_As_String(node)
	if !ok {
		return 0, false
	}

	return strconv.parse_int(value)
}

Yaml_As_Float :: proc(
	node: Yaml_Node,
) -> (f64, bool) {
	value, ok := Yaml_As_String(node)
	if !ok {
		return 0, false
	}

	return strconv.parse_f64(value)
}

Yaml_As_Bool :: proc(
	node: Yaml_Node,
) -> (bool, bool) {
	value, ok := Yaml_As_String(node)
	if !ok {
		return false, false
	}

	return strconv.parse_bool(value)
}

Yaml_Mapping_Count :: proc(
	node: Yaml_Node,
) -> int {
	if !Yaml_Is_Mapping(node) {
		return 0
	}

	start := node.data.mapping.pairs.start
	top := node.data.mapping.pairs.top

	if start == nil || top == nil {
		return 0
	}

	bytes := uintptr(top) - uintptr(start)

	return int(bytes / size_of(kineffi.yaml_node_pair_t))
}

Yaml_Sequence_Count :: proc(
	node: Yaml_Node,
) -> int {
	if !Yaml_Is_Sequence(node) {
		return 0
	}

	start := node.data.sequence.items.start
	top := node.data.sequence.items.top

	if start == nil || top == nil {
		return 0
	}

	bytes := uintptr(top) - uintptr(start)

	return int(bytes / size_of(kineffi.yaml_node_item_t))
}

Yaml_Count :: proc(node: Yaml_Node) -> int {
	if node == nil {
		return 0
	}

	#partial switch node.type {
	case .MAPPING_NODE:
		return Yaml_Mapping_Count(node)

	case .SEQUENCE_NODE:
		return Yaml_Sequence_Count(node)
	}

	return 0
}

Yaml_Get :: proc(
	document: ^Yaml_Document,
	node: Yaml_Node,
	key: string,
) -> Yaml_Node {
	if document == nil ||
	   !document.loaded ||
	   !Yaml_Is_Mapping(node) {
		return nil
	}

	start := node.data.mapping.pairs.start
	count := Yaml_Mapping_Count(node)

	if start == nil || count == 0 {
		return nil
	}

	pairs := mem.slice_ptr(
		start,
		count,
	)

	for pair in pairs {
		key_node := kineffi.yaml_document_get_node(
			&document.document,
			pair.key,
		)

		if key_node == nil {
			continue
		}

		key_value, ok := Yaml_As_String(key_node)
		if !ok {
			continue
		}

		if key_value == key {
			return kineffi.yaml_document_get_node(
				&document.document,
				pair.value,
			)
		}
	}

	return nil
}

Yaml_Index :: proc(
	document: ^Yaml_Document,
	node: Yaml_Node,
	index: int,
) -> Yaml_Node {
	if document == nil ||
	   !document.loaded ||
	   !Yaml_Is_Sequence(node) {
		return nil
	}

	count := Yaml_Sequence_Count(node)

	if index < 0 || index >= count {
		return nil
	}

	items := mem.slice_ptr(
		node.data.sequence.items.start,
		count,
	)

	return kineffi.yaml_document_get_node(
		&document.document,
		items[index],
	)
}

Yaml_Get_String :: proc(
	document: ^Yaml_Document,
	node: Yaml_Node,
	key: string,
) -> (string, bool) {
	return Yaml_As_String(
		Yaml_Get(document, node, key),
	)
}

Yaml_Get_Int :: proc(
	document: ^Yaml_Document,
	node: Yaml_Node,
	key: string,
) -> (int, bool) {
	return Yaml_As_Int(
		Yaml_Get(document, node, key),
	)
}

Yaml_Get_Float :: proc(
	document: ^Yaml_Document,
	node: Yaml_Node,
	key: string,
) -> (f64, bool) {
	return Yaml_As_Float(
		Yaml_Get(document, node, key),
	)
}

Yaml_Get_Bool :: proc(
	document: ^Yaml_Document,
	node: Yaml_Node,
	key: string,
) -> (bool, bool) {
	return Yaml_As_Bool(
		Yaml_Get(document, node, key),
	)
}