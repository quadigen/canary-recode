/**
 * @file yaml.h
 * @brief Public interface for libyaml.
 * 
 * Include the header file with the code:
 * @code
 * #include <yaml.h>
 * @endcode
 */
package kineffi

import "core:c/libc"
import "core:c"

foreign import lib "../../../vendor/build/vendor/libyaml/yaml.lib"

@(default_calling_convention="c")
foreign lib {
	/**
	* Get the library version as a string.
	*
	* @returns The function returns the pointer to a static string of the form
	* @c "X.Y.Z", where @c X is the major version number, @c Y is a minor version
	* number, and @c Z is the patch version number.
	*/
	yaml_get_version_string :: proc() -> cstring ---

	/**
	* Get the library version numbers.
	*
	* @param[out]      major   Major version number.
	* @param[out]      minor   Minor version number.
	* @param[out]      patch   Patch version number.
	*/
	yaml_get_version :: proc(major: ^i32, minor: ^i32, patch: ^i32) ---
}

/** The character type (UTF-8 octet). */
yaml_char_t :: u8

/** The version directive data. */
yaml_version_directive_s :: struct {
	/** The major version number. */
	major: i32,

	/** The minor version number. */
	minor: i32,
}

/** The version directive data. */
yaml_version_directive_t :: yaml_version_directive_s

/** The tag directive data. */
yaml_tag_directive_s :: struct {
	/** The tag handle. */
	handle: ^yaml_char_t,

	/** The tag prefix. */
	prefix: ^yaml_char_t,
}

/** The tag directive data. */
yaml_tag_directive_t :: yaml_tag_directive_s

/** The stream encoding. */
yaml_encoding_e :: enum i32 {
	/** Let the parser choose the encoding. */
	ANY_ENCODING     = 0,

	/** The default UTF-8 encoding. */
	UTF8_ENCODING    = 1,

	/** The UTF-16-LE encoding with BOM. */
	UTF16LE_ENCODING = 2,

	/** The UTF-16-BE encoding with BOM. */
	UTF16BE_ENCODING = 3,
}

/** The stream encoding. */
yaml_encoding_t :: yaml_encoding_e

/** Line break types. */
yaml_break_e :: enum i32 {
	/** Let the parser choose the break type. */
	ANY_BREAK  = 0,

	/** Use CR for line breaks (Mac style). */
	CR_BREAK   = 1,

	/** Use LN for line breaks (Unix style). */
	LN_BREAK   = 2,

	/** Use CR LN for line breaks (DOS style). */
	CRLN_BREAK = 3,
}

/** Line break types. */
yaml_break_t :: yaml_break_e

/** Many bad things could happen with the parser and emitter. */
yaml_error_type_e :: enum i32 {
	/** No error is produced. */
	NO_ERROR       = 0,

	/** Cannot allocate or reallocate a block of memory. */
	MEMORY_ERROR   = 1,

	/** Cannot read or decode the input stream. */
	READER_ERROR   = 2,

	/** Cannot scan the input stream. */
	SCANNER_ERROR  = 3,

	/** Cannot parse the input stream. */
	PARSER_ERROR   = 4,

	/** Cannot compose a YAML document. */
	COMPOSER_ERROR = 5,

	/** Cannot write to the output stream. */
	WRITER_ERROR   = 6,

	/** Cannot emit a YAML stream. */
	EMITTER_ERROR  = 7,
}

/** Many bad things could happen with the parser and emitter. */
yaml_error_type_t :: yaml_error_type_e

/** The pointer position. */
yaml_mark_s :: struct {
	/** The position index. */
	index: c.size_t,

	/** The position line. */
	line: c.size_t,

	/** The position column. */
	column: c.size_t,
}

/** The pointer position. */
yaml_mark_t :: yaml_mark_s

/** Scalar styles. */
yaml_scalar_style_e :: enum i32 {
	/** Let the emitter choose the style. */
	ANY_SCALAR_STYLE           = 0,

	/** The plain scalar style. */
	PLAIN_SCALAR_STYLE         = 1,

	/** The single-quoted scalar style. */
	SINGLE_QUOTED_SCALAR_STYLE = 2,

	/** The double-quoted scalar style. */
	DOUBLE_QUOTED_SCALAR_STYLE = 3,

	/** The literal scalar style. */
	LITERAL_SCALAR_STYLE       = 4,

	/** The folded scalar style. */
	FOLDED_SCALAR_STYLE        = 5,
}

/** Scalar styles. */
yaml_scalar_style_t :: yaml_scalar_style_e

/** Sequence styles. */
yaml_sequence_style_e :: enum i32 {
	/** Let the emitter choose the style. */
	ANY_SEQUENCE_STYLE   = 0,

	/** The block sequence style. */
	BLOCK_SEQUENCE_STYLE = 1,

	/** The flow sequence style. */
	FLOW_SEQUENCE_STYLE  = 2,
}

/** Sequence styles. */
yaml_sequence_style_t :: yaml_sequence_style_e

/** Mapping styles. */
yaml_mapping_style_e :: enum i32 {
	/** Let the emitter choose the style. */
	ANY_MAPPING_STYLE   = 0,

	/** The block mapping style. */
	BLOCK_MAPPING_STYLE = 1,

	/** The flow mapping style. */
	FLOW_MAPPING_STYLE  = 2,
}

/** Mapping styles. */
yaml_mapping_style_t :: yaml_mapping_style_e

/** Token types. */
yaml_token_type_e :: enum i32 {
	/** An empty token. */
	NO_TOKEN                   = 0,

	/** A STREAM-START token. */
	STREAM_START_TOKEN         = 1,

	/** A STREAM-END token. */
	STREAM_END_TOKEN           = 2,

	/** A VERSION-DIRECTIVE token. */
	VERSION_DIRECTIVE_TOKEN    = 3,

	/** A TAG-DIRECTIVE token. */
	TAG_DIRECTIVE_TOKEN        = 4,

	/** A DOCUMENT-START token. */
	DOCUMENT_START_TOKEN       = 5,

	/** A DOCUMENT-END token. */
	DOCUMENT_END_TOKEN         = 6,

	/** A BLOCK-SEQUENCE-START token. */
	BLOCK_SEQUENCE_START_TOKEN = 7,

	/** A BLOCK-MAPPING-START token. */
	BLOCK_MAPPING_START_TOKEN  = 8,

	/** A BLOCK-END token. */
	BLOCK_END_TOKEN            = 9,

	/** A FLOW-SEQUENCE-START token. */
	FLOW_SEQUENCE_START_TOKEN  = 10,

	/** A FLOW-SEQUENCE-END token. */
	FLOW_SEQUENCE_END_TOKEN    = 11,

	/** A FLOW-MAPPING-START token. */
	FLOW_MAPPING_START_TOKEN   = 12,

	/** A FLOW-MAPPING-END token. */
	FLOW_MAPPING_END_TOKEN     = 13,

	/** A BLOCK-ENTRY token. */
	BLOCK_ENTRY_TOKEN          = 14,

	/** A FLOW-ENTRY token. */
	FLOW_ENTRY_TOKEN           = 15,

	/** A KEY token. */
	KEY_TOKEN                  = 16,

	/** A VALUE token. */
	VALUE_TOKEN                = 17,

	/** An ALIAS token. */
	ALIAS_TOKEN                = 18,

	/** An ANCHOR token. */
	ANCHOR_TOKEN               = 19,

	/** A TAG token. */
	TAG_TOKEN                  = 20,

	/** A SCALAR token. */
	SCALAR_TOKEN               = 21,
}

/** Token types. */
yaml_token_type_t :: yaml_token_type_e

/** The token structure. */
yaml_token_s :: struct {
	/** The token type. */
	type: yaml_token_type_t,

	data: struct #raw_union {
		stream_start: struct {
			/** The stream encoding. */
			encoding: yaml_encoding_t,
		},

		alias: struct {
			/** The alias value. */
			value: ^yaml_char_t,
		},

		anchor: struct {
			/** The anchor value. */
			value: ^yaml_char_t,
		},

		tag: struct {
			/** The tag handle. */
			handle: ^yaml_char_t,

			/** The tag suffix. */
			suffix: ^yaml_char_t,
		},

		scalar: struct {
			/** The scalar value. */
			value: ^yaml_char_t,

			/** The length of the scalar value. */
			length: c.size_t,

			/** The scalar style. */
			style: yaml_scalar_style_t,
		},

		version_directive: struct {
			/** The major version number. */
			major: i32,

			/** The minor version number. */
			minor: i32,
		},

		tag_directive: struct {
			/** The tag handle. */
			handle: ^yaml_char_t,

			/** The tag prefix. */
			prefix: ^yaml_char_t,
		},
	},

	/** The beginning of the token. */
	start_mark: yaml_mark_t,

	/** The end of the token. */
	end_mark: yaml_mark_t,
}

/** The token structure. */
yaml_token_t :: yaml_token_s

@(default_calling_convention="c")
foreign lib {
	/**
	* Free any memory allocated for a token object.
	*
	* @param[in,out]   token   A token object.
	*/
	yaml_token_delete :: proc(token: ^yaml_token_t) ---
}

/** Event types. */
yaml_event_type_e :: enum i32 {
	/** An empty event. */
	NO_EVENT             = 0,

	/** A STREAM-START event. */
	STREAM_START_EVENT   = 1,

	/** A STREAM-END event. */
	STREAM_END_EVENT     = 2,

	/** A DOCUMENT-START event. */
	DOCUMENT_START_EVENT = 3,

	/** A DOCUMENT-END event. */
	DOCUMENT_END_EVENT   = 4,

	/** An ALIAS event. */
	ALIAS_EVENT          = 5,

	/** A SCALAR event. */
	SCALAR_EVENT         = 6,

	/** A SEQUENCE-START event. */
	SEQUENCE_START_EVENT = 7,

	/** A SEQUENCE-END event. */
	SEQUENCE_END_EVENT   = 8,

	/** A MAPPING-START event. */
	MAPPING_START_EVENT  = 9,

	/** A MAPPING-END event. */
	MAPPING_END_EVENT    = 10,
}

/** Event types. */
yaml_event_type_t :: yaml_event_type_e

/** The event structure. */
yaml_event_s :: struct {
	/** The event type. */
	type: yaml_event_type_t,

	data: struct #raw_union {
		stream_start: struct {
			/** The document encoding. */
			encoding: yaml_encoding_t,
		},

		document_start: struct {
			/** The version directive. */
			version_directive: ^yaml_version_directive_t,

			tag_directives: struct {
				/** The beginning of the tag directives list. */
				start: ^yaml_tag_directive_t,

				/** The end of the tag directives list. */
				end: ^yaml_tag_directive_t,
			},

			/** Is the document indicator implicit? */
			implicit: i32,
		},

		document_end: struct {
			/** Is the document end indicator implicit? */
			implicit: i32,
		},

		alias: struct {
			/** The anchor. */
			anchor: ^yaml_char_t,
		},

		scalar: struct {
			/** The anchor. */
			anchor: ^yaml_char_t,

			/** The tag. */
			tag: ^yaml_char_t,

			/** The scalar value. */
			value: ^yaml_char_t,

			/** The length of the scalar value. */
			length: c.size_t,

			/** Is the tag optional for the plain style? */
			plain_implicit: i32,

			/** Is the tag optional for any non-plain style? */
			quoted_implicit: i32,

			/** The scalar style. */
			style: yaml_scalar_style_t,
		},

		sequence_start: struct {
			/** The anchor. */
			anchor: ^yaml_char_t,

			/** The tag. */
			tag: ^yaml_char_t,

			/** Is the tag optional? */
			implicit: i32,

			/** The sequence style. */
			style: yaml_sequence_style_t,
		},

		mapping_start: struct {
			/** The anchor. */
			anchor: ^yaml_char_t,

			/** The tag. */
			tag: ^yaml_char_t,

			/** Is the tag optional? */
			implicit: i32,

			/** The mapping style. */
			style: yaml_mapping_style_t,
		},
	},

	/** The beginning of the event. */
	start_mark: yaml_mark_t,

	/** The end of the event. */
	end_mark: yaml_mark_t,
}

/** The event structure. */
yaml_event_t :: yaml_event_s

@(default_calling_convention="c")
foreign lib {
	/**
	* Create the STREAM-START event.
	*
	* @param[out]      event       An empty event object.
	* @param[in]       encoding    The stream encoding.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_stream_start_event_initialize :: proc(event: ^yaml_event_t, encoding: yaml_encoding_t) -> i32 ---

	/**
	* Create the STREAM-END event.
	*
	* @param[out]      event       An empty event object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_stream_end_event_initialize :: proc(event: ^yaml_event_t) -> i32 ---

	/**
	* Create the DOCUMENT-START event.
	*
	* The @a implicit argument is considered as a stylistic parameter and may be
	* ignored by the emitter.
	*
	* @param[out]      event                   An empty event object.
	* @param[in]       version_directive       The %YAML directive value or
	*                                          @c NULL.
	* @param[in]       tag_directives_start    The beginning of the %TAG
	*                                          directives list.
	* @param[in]       tag_directives_end      The end of the %TAG directives
	*                                          list.
	* @param[in]       implicit                If the document start indicator is
	*                                          implicit.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_document_start_event_initialize :: proc(event: ^yaml_event_t, version_directive: ^yaml_version_directive_t, tag_directives_start: ^yaml_tag_directive_t, tag_directives_end: ^yaml_tag_directive_t, implicit: i32) -> i32 ---

	/**
	* Create the DOCUMENT-END event.
	*
	* The @a implicit argument is considered as a stylistic parameter and may be
	* ignored by the emitter.
	*
	* @param[out]      event       An empty event object.
	* @param[in]       implicit    If the document end indicator is implicit.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_document_end_event_initialize :: proc(event: ^yaml_event_t, implicit: i32) -> i32 ---

	/**
	* Create an ALIAS event.
	*
	* @param[out]      event       An empty event object.
	* @param[in]       anchor      The anchor value.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_alias_event_initialize :: proc(event: ^yaml_event_t, anchor: ^yaml_char_t) -> i32 ---

	/**
	* Create a SCALAR event.
	*
	* The @a style argument may be ignored by the emitter.
	*
	* Either the @a tag attribute or one of the @a plain_implicit and
	* @a quoted_implicit flags must be set.
	*
	* @param[out]      event           An empty event object.
	* @param[in]       anchor          The scalar anchor or @c NULL.
	* @param[in]       tag             The scalar tag or @c NULL.
	* @param[in]       value           The scalar value.
	* @param[in]       length          The length of the scalar value.
	* @param[in]       plain_implicit  If the tag may be omitted for the plain
	*                                  style.
	* @param[in]       quoted_implicit If the tag may be omitted for any
	*                                  non-plain style.
	* @param[in]       style           The scalar style.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_scalar_event_initialize :: proc(event: ^yaml_event_t, anchor: ^yaml_char_t, tag: ^yaml_char_t, value: ^yaml_char_t, length: i32, plain_implicit: i32, quoted_implicit: i32, style: yaml_scalar_style_t) -> i32 ---

	/**
	* Create a SEQUENCE-START event.
	*
	* The @a style argument may be ignored by the emitter.
	*
	* Either the @a tag attribute or the @a implicit flag must be set.
	*
	* @param[out]      event       An empty event object.
	* @param[in]       anchor      The sequence anchor or @c NULL.
	* @param[in]       tag         The sequence tag or @c NULL.
	* @param[in]       implicit    If the tag may be omitted.
	* @param[in]       style       The sequence style.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_sequence_start_event_initialize :: proc(event: ^yaml_event_t, anchor: ^yaml_char_t, tag: ^yaml_char_t, implicit: i32, style: yaml_sequence_style_t) -> i32 ---

	/**
	* Create a SEQUENCE-END event.
	*
	* @param[out]      event       An empty event object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_sequence_end_event_initialize :: proc(event: ^yaml_event_t) -> i32 ---

	/**
	* Create a MAPPING-START event.
	*
	* The @a style argument may be ignored by the emitter.
	*
	* Either the @a tag attribute or the @a implicit flag must be set.
	*
	* @param[out]      event       An empty event object.
	* @param[in]       anchor      The mapping anchor or @c NULL.
	* @param[in]       tag         The mapping tag or @c NULL.
	* @param[in]       implicit    If the tag may be omitted.
	* @param[in]       style       The mapping style.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_mapping_start_event_initialize :: proc(event: ^yaml_event_t, anchor: ^yaml_char_t, tag: ^yaml_char_t, implicit: i32, style: yaml_mapping_style_t) -> i32 ---

	/**
	* Create a MAPPING-END event.
	*
	* @param[out]      event       An empty event object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_mapping_end_event_initialize :: proc(event: ^yaml_event_t) -> i32 ---

	/**
	* Free any memory allocated for an event object.
	*
	* @param[in,out]   event   An event object.
	*/
	yaml_event_delete :: proc(event: ^yaml_event_t) ---
}

/** @} */

/**
* @defgroup nodes Nodes
* @{
*/

/** The tag @c !!null with the only possible value: @c null. */
YAML_NULL_TAG       :: "tag:yaml.org,2002:null"

/** The tag @c !!bool with the values: @c true and @c false. */
YAML_BOOL_TAG       :: "tag:yaml.org,2002:bool"

/** The tag @c !!str for string values. */
YAML_STR_TAG        :: "tag:yaml.org,2002:str"

/** The tag @c !!int for integer values. */
YAML_INT_TAG        :: "tag:yaml.org,2002:int"

/** The tag @c !!float for float values. */
YAML_FLOAT_TAG      :: "tag:yaml.org,2002:float"

/** The tag @c !!timestamp for date and time values. */
YAML_TIMESTAMP_TAG  :: "tag:yaml.org,2002:timestamp"

/** The tag @c !!seq is used to denote sequences. */
YAML_SEQ_TAG        :: "tag:yaml.org,2002:seq"

/** The tag @c !!map is used to denote mapping. */
YAML_MAP_TAG        :: "tag:yaml.org,2002:map"

/** The default scalar tag is @c !!str. */
YAML_DEFAULT_SCALAR_TAG     :: YAML_STR_TAG

/** The default sequence tag is @c !!seq. */
YAML_DEFAULT_SEQUENCE_TAG   :: YAML_SEQ_TAG

/** The default mapping tag is @c !!map. */
YAML_DEFAULT_MAPPING_TAG    :: YAML_MAP_TAG

/** Node types. */
yaml_node_type_e :: enum i32 {
	/** An empty node. */
	NO_NODE       = 0,

	/** A scalar node. */
	SCALAR_NODE   = 1,

	/** A sequence node. */
	SEQUENCE_NODE = 2,

	/** A mapping node. */
	MAPPING_NODE  = 3,
}

/** Node types. */
yaml_node_type_t :: yaml_node_type_e

/** The forward definition of a document node structure. */
yaml_node_t :: yaml_node_s

/** An element of a sequence node. */
yaml_node_item_t :: i32

/** An element of a mapping node. */
yaml_node_pair_s :: struct {
	/** The key of the element. */
	key: i32,

	/** The value of the element. */
	value: i32,
}

/** An element of a mapping node. */
yaml_node_pair_t :: yaml_node_pair_s

/** The node structure. */
yaml_node_s :: struct {
	/** The node type. */
	type: yaml_node_type_t,

	/** The node tag. */
	tag: ^yaml_char_t,

	data: struct #raw_union {
		scalar: struct {
			/** The scalar value. */
			value: ^yaml_char_t,

			/** The length of the scalar value. */
			length: c.size_t,

			/** The scalar style. */
			style: yaml_scalar_style_t,
		},

		sequence: struct {
			items: struct {
				/** The beginning of the stack. */
				start: ^yaml_node_item_t,

				/** The end of the stack. */
				end: ^yaml_node_item_t,

				/** The top of the stack. */
				top: ^yaml_node_item_t,
			},

			/** The sequence style. */
			style: yaml_sequence_style_t,
		},

		mapping: struct {
			pairs: struct {
				/** The beginning of the stack. */
				start: ^yaml_node_pair_t,

				/** The end of the stack. */
				end: ^yaml_node_pair_t,

				/** The top of the stack. */
				top: ^yaml_node_pair_t,
			},

			/** The mapping style. */
			style: yaml_mapping_style_t,
		},
	},

	/** The beginning of the node. */
	start_mark: yaml_mark_t,

	/** The end of the node. */
	end_mark: yaml_mark_t,
}

/** The document structure. */
yaml_document_s :: struct {
	nodes: struct {
		/** The beginning of the stack. */
		start: ^yaml_node_t,

		/** The end of the stack. */
		end: ^yaml_node_t,

		/** The top of the stack. */
		top: ^yaml_node_t,
	},

	/** The version directive. */
	version_directive: ^yaml_version_directive_t,

	tag_directives: struct {
		/** The beginning of the tag directives list. */
		start: ^yaml_tag_directive_t,

		/** The end of the tag directives list. */
		end: ^yaml_tag_directive_t,
	},

	/** Is the document start indicator implicit? */
	start_implicit: i32,

	/** Is the document end indicator implicit? */
	end_implicit: i32,

	/** The beginning of the document. */
	start_mark: yaml_mark_t,

	/** The end of the document. */
	end_mark: yaml_mark_t,
}

/** The document structure. */
yaml_document_t :: yaml_document_s

@(default_calling_convention="c")
foreign lib {
	/**
	* Create a YAML document.
	*
	* @param[out]      document                An empty document object.
	* @param[in]       version_directive       The %YAML directive value or
	*                                          @c NULL.
	* @param[in]       tag_directives_start    The beginning of the %TAG
	*                                          directives list.
	* @param[in]       tag_directives_end      The end of the %TAG directives
	*                                          list.
	* @param[in]       start_implicit          If the document start indicator is
	*                                          implicit.
	* @param[in]       end_implicit            If the document end indicator is
	*                                          implicit.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_document_initialize :: proc(document: ^yaml_document_t, version_directive: ^yaml_version_directive_t, tag_directives_start: ^yaml_tag_directive_t, tag_directives_end: ^yaml_tag_directive_t, start_implicit: i32, end_implicit: i32) -> i32 ---

	/**
	* Delete a YAML document and all its nodes.
	*
	* @param[in,out]   document        A document object.
	*/
	yaml_document_delete :: proc(document: ^yaml_document_t) ---

	/**
	* Get a node of a YAML document.
	*
	* The pointer returned by this function is valid until any of the functions
	* modifying the documents are called.
	*
	* @param[in]       document        A document object.
	* @param[in]       index           The node id.
	*
	* @returns the node objct or @c NULL if @c node_id is out of range.
	*/
	yaml_document_get_node :: proc(document: ^yaml_document_t, index: i32) -> ^yaml_node_t ---

	/**
	* Get the root of a YAML document node.
	*
	* The root object is the first object added to the document.
	*
	* The pointer returned by this function is valid until any of the functions
	* modifying the documents are called.
	*
	* An empty document produced by the parser signifies the end of a YAML
	* stream.
	*
	* @param[in]       document        A document object.
	*
	* @returns the node object or @c NULL if the document is empty.
	*/
	yaml_document_get_root_node :: proc(document: ^yaml_document_t) -> ^yaml_node_t ---

	/**
	* Create a SCALAR node and attach it to the document.
	*
	* The @a style argument may be ignored by the emitter.
	*
	* @param[in,out]   document        A document object.
	* @param[in]       tag             The scalar tag.
	* @param[in]       value           The scalar value.
	* @param[in]       length          The length of the scalar value.
	* @param[in]       style           The scalar style.
	*
	* @returns the node id or @c 0 on error.
	*/
	yaml_document_add_scalar :: proc(document: ^yaml_document_t, tag: ^yaml_char_t, value: ^yaml_char_t, length: i32, style: yaml_scalar_style_t) -> i32 ---

	/**
	* Create a SEQUENCE node and attach it to the document.
	*
	* The @a style argument may be ignored by the emitter.
	*
	* @param[in,out]   document    A document object.
	* @param[in]       tag         The sequence tag.
	* @param[in]       style       The sequence style.
	*
	* @returns the node id or @c 0 on error.
	*/
	yaml_document_add_sequence :: proc(document: ^yaml_document_t, tag: ^yaml_char_t, style: yaml_sequence_style_t) -> i32 ---

	/**
	* Create a MAPPING node and attach it to the document.
	*
	* The @a style argument may be ignored by the emitter.
	*
	* @param[in,out]   document    A document object.
	* @param[in]       tag         The sequence tag.
	* @param[in]       style       The sequence style.
	*
	* @returns the node id or @c 0 on error.
	*/
	yaml_document_add_mapping :: proc(document: ^yaml_document_t, tag: ^yaml_char_t, style: yaml_mapping_style_t) -> i32 ---

	/**
	* Add an item to a SEQUENCE node.
	*
	* @param[in,out]   document    A document object.
	* @param[in]       sequence    The sequence node id.
	* @param[in]       item        The item node id.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_document_append_sequence_item :: proc(document: ^yaml_document_t, sequence: i32, item: i32) -> i32 ---

	/**
	* Add a pair of a key and a value to a MAPPING node.
	*
	* @param[in,out]   document    A document object.
	* @param[in]       mapping     The mapping node id.
	* @param[in]       key         The key node id.
	* @param[in]       value       The value node id.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_document_append_mapping_pair :: proc(document: ^yaml_document_t, mapping: i32, key: i32, value: i32) -> i32 ---
}

/**
* The prototype of a read handler.
*
* The read handler is called when the parser needs to read more bytes from the
* source.  The handler should write not more than @a size bytes to the @a
* buffer.  The number of written bytes should be set to the @a length variable.
*
* @param[in,out]   data        A pointer to an application data specified by
*                              yaml_parser_set_input().
* @param[out]      buffer      The buffer to write the data from the source.
* @param[in]       size        The size of the buffer.
* @param[out]      size_read   The actual number of bytes read from the source.
*
* @returns On success, the handler should return @c 1.  If the handler failed,
* the returned value should be @c 0.  On EOF, the handler should set the
* @a size_read to @c 0 and return @c 1.
*/
yaml_read_handler_t :: proc "c" (data: rawptr, buffer: ^u8, size: c.size_t, size_read: ^c.size_t) -> i32

/**
* This structure holds information about a potential simple key.
*/
yaml_simple_key_s :: struct {
	/** Is a simple key possible? */
	possible: i32,

	/** Is a simple key required? */
	required: i32,

	/** The number of the token. */
	token_number: c.size_t,

	/** The position mark. */
	mark: yaml_mark_t,
}

/**
* This structure holds information about a potential simple key.
*/
yaml_simple_key_t :: yaml_simple_key_s

/**
* The states of the parser.
*/
yaml_parser_state_e :: enum i32 {
	/** Expect STREAM-START. */
	STREAM_START_STATE                      = 0,

	/** Expect the beginning of an implicit document. */
	IMPLICIT_DOCUMENT_START_STATE           = 1,

	/** Expect DOCUMENT-START. */
	DOCUMENT_START_STATE                    = 2,

	/** Expect the content of a document. */
	DOCUMENT_CONTENT_STATE                  = 3,

	/** Expect DOCUMENT-END. */
	DOCUMENT_END_STATE                      = 4,

	/** Expect a block node. */
	BLOCK_NODE_STATE                        = 5,

	/** Expect a block node or indentless sequence. */
	BLOCK_NODE_OR_INDENTLESS_SEQUENCE_STATE = 6,

	/** Expect a flow node. */
	FLOW_NODE_STATE                         = 7,

	/** Expect the first entry of a block sequence. */
	BLOCK_SEQUENCE_FIRST_ENTRY_STATE        = 8,

	/** Expect an entry of a block sequence. */
	BLOCK_SEQUENCE_ENTRY_STATE              = 9,

	/** Expect an entry of an indentless sequence. */
	INDENTLESS_SEQUENCE_ENTRY_STATE         = 10,

	/** Expect the first key of a block mapping. */
	BLOCK_MAPPING_FIRST_KEY_STATE           = 11,

	/** Expect a block mapping key. */
	BLOCK_MAPPING_KEY_STATE                 = 12,

	/** Expect a block mapping value. */
	BLOCK_MAPPING_VALUE_STATE               = 13,

	/** Expect the first entry of a flow sequence. */
	FLOW_SEQUENCE_FIRST_ENTRY_STATE         = 14,

	/** Expect an entry of a flow sequence. */
	FLOW_SEQUENCE_ENTRY_STATE               = 15,

	/** Expect a key of an ordered mapping. */
	FLOW_SEQUENCE_ENTRY_MAPPING_KEY_STATE   = 16,

	/** Expect a value of an ordered mapping. */
	FLOW_SEQUENCE_ENTRY_MAPPING_VALUE_STATE = 17,

	/** Expect the and of an ordered mapping entry. */
	FLOW_SEQUENCE_ENTRY_MAPPING_END_STATE   = 18,

	/** Expect the first key of a flow mapping. */
	FLOW_MAPPING_FIRST_KEY_STATE            = 19,

	/** Expect a key of a flow mapping. */
	FLOW_MAPPING_KEY_STATE                  = 20,

	/** Expect a value of a flow mapping. */
	FLOW_MAPPING_VALUE_STATE                = 21,

	/** Expect an empty value of a flow mapping. */
	FLOW_MAPPING_EMPTY_VALUE_STATE          = 22,

	/** Expect nothing. */
	END_STATE                               = 23,
}

/**
* The states of the parser.
*/
yaml_parser_state_t :: yaml_parser_state_e

/**
* This structure holds aliases data.
*/
yaml_alias_data_s :: struct {
	/** The anchor. */
	anchor: ^yaml_char_t,

	/** The node id. */
	index: i32,

	/** The anchor mark. */
	mark: yaml_mark_t,
}

/**
* This structure holds aliases data.
*/
yaml_alias_data_t :: yaml_alias_data_s

/**
* The parser structure.
*
* All members are internal.  Manage the structure using the @c yaml_parser_
* family of functions.
*/
yaml_parser_s :: struct {
	/**
	* @name Error handling
	* @{
	*/
	
	/** Error type. */
	error: yaml_error_type_t,

	/** Error description. */
	problem: cstring,

	/** The byte about which the problem occurred. */
	problem_offset: c.size_t,

	/** The problematic value (@c -1 is none). */
	problem_value: i32,

	/** The problem position. */
	problem_mark: yaml_mark_t,

	/** The error context. */
	_context: cstring,

	/** The context position. */
	context_mark: yaml_mark_t,

	/**
	* @}
	*/
	
	/**
	* @name Reader stuff
	* @{
	*/
	
	/** Read handler. */
	read_handler: yaml_read_handler_t,

	/** A pointer for passing to the read handler. */
	read_handler_data: rawptr,

	input: struct #raw_union {
		_string: struct {
			/** The string start pointer. */
			start: ^u8,

			/** The string end pointer. */
			end: ^u8,

			/** The string current position. */
			current: ^u8,
		},

		/** File input data. */
		file: ^libc.FILE,
	},

	/** EOF flag */
	eof: i32,

	buffer: struct {
		/** The beginning of the buffer. */
		start: ^yaml_char_t,

		/** The end of the buffer. */
		end: ^yaml_char_t,

		/** The current position of the buffer. */
		pointer: ^yaml_char_t,

		/** The last filled position of the buffer. */
		last: ^yaml_char_t,
	},

	/* The number of unread characters in the buffer. */
	unread: c.size_t,

	raw_buffer: struct {
		/** The beginning of the buffer. */
		start: ^u8,

		/** The end of the buffer. */
		end: ^u8,

		/** The current position of the buffer. */
		pointer: ^u8,

		/** The last filled position of the buffer. */
		last: ^u8,
	},

	/** The input encoding. */
	encoding: yaml_encoding_t,

	/** The offset of the current position (in bytes). */
	offset: c.size_t,

	/** The mark of the current position. */
	mark: yaml_mark_t,

	/**
	* @}
	*/
	
	/**
	* @name Scanner stuff
	* @{
	*/
	
	/** Have we started to scan the input stream? */
	stream_start_produced: i32,

	/** Have we reached the end of the input stream? */
	stream_end_produced: i32,

	/** The number of unclosed '[' and '{' indicators. */
	flow_level: i32,

	tokens: struct {
		/** The beginning of the tokens queue. */
		start: ^yaml_token_t,

		/** The end of the tokens queue. */
		end: ^yaml_token_t,

		/** The head of the tokens queue. */
		head: ^yaml_token_t,

		/** The tail of the tokens queue. */
		tail: ^yaml_token_t,
	},

	/** The number of tokens fetched from the queue. */
	tokens_parsed: c.size_t,

	/** Does the tokens queue contain a token ready for dequeueing. */
	token_available: i32,

	indents: struct {
		/** The beginning of the stack. */
		start: ^i32,

		/** The end of the stack. */
		end: ^i32,

		/** The top of the stack. */
		top: ^i32,
	},

	/** The current indentation level. */
	indent: i32,

	/** May a simple key occur at the current position? */
	simple_key_allowed: i32,

	simple_keys: struct {
		/** The beginning of the stack. */
		start: ^yaml_simple_key_t,

		/** The end of the stack. */
		end: ^yaml_simple_key_t,

		/** The top of the stack. */
		top: ^yaml_simple_key_t,
	},

	states: struct {
		/** The beginning of the stack. */
		start: ^yaml_parser_state_t,

		/** The end of the stack. */
		end: ^yaml_parser_state_t,

		/** The top of the stack. */
		top: ^yaml_parser_state_t,
	},

	/** The current parser state. */
	state: yaml_parser_state_t,

	marks: struct {
		/** The beginning of the stack. */
		start: ^yaml_mark_t,

		/** The end of the stack. */
		end: ^yaml_mark_t,

		/** The top of the stack. */
		top: ^yaml_mark_t,
	},

	tag_directives: struct {
		/** The beginning of the list. */
		start: ^yaml_tag_directive_t,

		/** The end of the list. */
		end: ^yaml_tag_directive_t,

		/** The top of the list. */
		top: ^yaml_tag_directive_t,
	},

	aliases: struct {
		/** The beginning of the list. */
		start: ^yaml_alias_data_t,

		/** The end of the list. */
		end: ^yaml_alias_data_t,

		/** The top of the list. */
		top: ^yaml_alias_data_t,
	},

	/** The currently parsed document. */
	document: ^yaml_document_t,
}

/**
* The parser structure.
*
* All members are internal.  Manage the structure using the @c yaml_parser_
* family of functions.
*/
yaml_parser_t :: yaml_parser_s

@(default_calling_convention="c")
foreign lib {
	/**
	* Initialize a parser.
	*
	* This function creates a new parser object.  An application is responsible
	* for destroying the object using the yaml_parser_delete() function.
	*
	* @param[out]      parser  An empty parser object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_parser_initialize :: proc(parser: ^yaml_parser_t) -> i32 ---

	/**
	* Destroy a parser.
	*
	* @param[in,out]   parser  A parser object.
	*/
	yaml_parser_delete :: proc(parser: ^yaml_parser_t) ---

	/**
	* Set a string input.
	*
	* Note that the @a input pointer must be valid while the @a parser object
	* exists.  The application is responsible for destroying @a input after
	* destroying the @a parser.
	*
	* @param[in,out]   parser  A parser object.
	* @param[in]       input   A source data.
	* @param[in]       size    The length of the source data in bytes.
	*/
	yaml_parser_set_input_string :: proc(parser: ^yaml_parser_t, input: ^u8, size: c.size_t) ---

	/**
	* Set a file input.
	*
	* @a file should be a file object open for reading.  The application is
	* responsible for closing the @a file.
	*
	* @param[in,out]   parser  A parser object.
	* @param[in]       file    An open file.
	*/
	yaml_parser_set_input_file :: proc(parser: ^yaml_parser_t, file: ^libc.FILE) ---

	/**
	* Set a generic input handler.
	*
	* @param[in,out]   parser  A parser object.
	* @param[in]       handler A read handler.
	* @param[in]       data    Any application data for passing to the read
	*                          handler.
	*/
	yaml_parser_set_input :: proc(parser: ^yaml_parser_t, handler: yaml_read_handler_t, data: rawptr) ---

	/**
	* Set the source encoding.
	*
	* @param[in,out]   parser      A parser object.
	* @param[in]       encoding    The source encoding.
	*/
	yaml_parser_set_encoding :: proc(parser: ^yaml_parser_t, encoding: yaml_encoding_t) ---

	/**
	* Scan the input stream and produce the next token.
	*
	* Call the function subsequently to produce a sequence of tokens corresponding
	* to the input stream.  The initial token has the type
	* @c YAML_STREAM_START_TOKEN while the ending token has the type
	* @c YAML_STREAM_END_TOKEN.
	*
	* An application is responsible for freeing any buffers associated with the
	* produced token object using the @c yaml_token_delete function.
	*
	* An application must not alternate the calls of yaml_parser_scan() with the
	* calls of yaml_parser_parse() or yaml_parser_load(). Doing this will break
	* the parser.
	*
	* @param[in,out]   parser      A parser object.
	* @param[out]      token       An empty token object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_parser_scan :: proc(parser: ^yaml_parser_t, token: ^yaml_token_t) -> i32 ---

	/**
	* Parse the input stream and produce the next parsing event.
	*
	* Call the function subsequently to produce a sequence of events corresponding
	* to the input stream.  The initial event has the type
	* @c YAML_STREAM_START_EVENT while the ending event has the type
	* @c YAML_STREAM_END_EVENT.
	*
	* An application is responsible for freeing any buffers associated with the
	* produced event object using the yaml_event_delete() function.
	*
	* An application must not alternate the calls of yaml_parser_parse() with the
	* calls of yaml_parser_scan() or yaml_parser_load(). Doing this will break the
	* parser.
	*
	* @param[in,out]   parser      A parser object.
	* @param[out]      event       An empty event object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_parser_parse :: proc(parser: ^yaml_parser_t, event: ^yaml_event_t) -> i32 ---

	/**
	* Parse the input stream and produce the next YAML document.
	*
	* Call this function subsequently to produce a sequence of documents
	* constituting the input stream.
	*
	* If the produced document has no root node, it means that the document
	* end has been reached.
	*
	* An application is responsible for freeing any data associated with the
	* produced document object using the yaml_document_delete() function.
	*
	* An application must not alternate the calls of yaml_parser_load() with the
	* calls of yaml_parser_scan() or yaml_parser_parse(). Doing this will break
	* the parser.
	*
	* @param[in,out]   parser      A parser object.
	* @param[out]      document    An empty document object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_parser_load :: proc(parser: ^yaml_parser_t, document: ^yaml_document_t) -> i32 ---

	/**
	* Get the maximum depth of nesting.
	*
	* Default: 1000
	*
	* Each nesting level increases the stack and the number of previous
	* starting events that the parser has to check.
	*
	* @returns The maximum number of allowed nested events.
	*/
	yaml_get_max_nest_level :: proc() -> i32 ---

	/**
	* Set the maximum depth of nesting.
	*
	* Each nesting level increases the stack and the number of previous
	* starting events that the parser has to check.
	*
	* @param[in]       max         The maximum number of allowed nested events
	*/
	yaml_set_max_nest_level :: proc(max: i32) ---
}

/**
* The prototype of a write handler.
*
* The write handler is called when the emitter needs to flush the accumulated
* characters to the output.  The handler should write @a size bytes of the
* @a buffer to the output.
*
* @param[in,out]   data        A pointer to an application data specified by
*                              yaml_emitter_set_output().
* @param[in]       buffer      The buffer with bytes to be written.
* @param[in]       size        The size of the buffer.
*
* @returns On success, the handler should return @c 1.  If the handler failed,
* the returned value should be @c 0.
*/
yaml_write_handler_t :: proc "c" (data: rawptr, buffer: ^u8, size: c.size_t) -> i32

/** The emitter states. */
yaml_emitter_state_e :: enum i32 {
	/** Expect STREAM-START. */
	STREAM_START_STATE               = 0,

	/** Expect the first DOCUMENT-START or STREAM-END. */
	FIRST_DOCUMENT_START_STATE       = 1,

	/** Expect DOCUMENT-START or STREAM-END. */
	DOCUMENT_START_STATE             = 2,

	/** Expect the content of a document. */
	DOCUMENT_CONTENT_STATE           = 3,

	/** Expect DOCUMENT-END. */
	DOCUMENT_END_STATE               = 4,

	/** Expect the first item of a flow sequence. */
	FLOW_SEQUENCE_FIRST_ITEM_STATE   = 5,

	/** Expect an item of a flow sequence. */
	FLOW_SEQUENCE_ITEM_STATE         = 6,

	/** Expect the first key of a flow mapping. */
	FLOW_MAPPING_FIRST_KEY_STATE     = 7,

	/** Expect a key of a flow mapping. */
	FLOW_MAPPING_KEY_STATE           = 8,

	/** Expect a value for a simple key of a flow mapping. */
	FLOW_MAPPING_SIMPLE_VALUE_STATE  = 9,

	/** Expect a value of a flow mapping. */
	FLOW_MAPPING_VALUE_STATE         = 10,

	/** Expect the first item of a block sequence. */
	BLOCK_SEQUENCE_FIRST_ITEM_STATE  = 11,

	/** Expect an item of a block sequence. */
	BLOCK_SEQUENCE_ITEM_STATE        = 12,

	/** Expect the first key of a block mapping. */
	BLOCK_MAPPING_FIRST_KEY_STATE    = 13,

	/** Expect the key of a block mapping. */
	BLOCK_MAPPING_KEY_STATE          = 14,

	/** Expect a value for a simple key of a block mapping. */
	BLOCK_MAPPING_SIMPLE_VALUE_STATE = 15,

	/** Expect a value of a block mapping. */
	BLOCK_MAPPING_VALUE_STATE        = 16,

	/** Expect nothing. */
	END_STATE                        = 17,
}

/** The emitter states. */
yaml_emitter_state_t :: yaml_emitter_state_e

/* This is needed for C++ */
yaml_anchors_s :: struct {
	/** The number of references. */
	references: i32,

	/** The anchor id. */
	anchor: i32,

	/** If the node has been emitted? */
	serialized: i32,
}

/* This is needed for C++ */
yaml_anchors_t :: yaml_anchors_s

/**
* The emitter structure.
*
* All members are internal.  Manage the structure using the @c yaml_emitter_
* family of functions.
*/
yaml_emitter_s :: struct {
	/**
	* @name Error handling
	* @{
	*/
	
	/** Error type. */
	error: yaml_error_type_t,

	/** Error description. */
	problem: cstring,

	/**
	* @}
	*/
	
	/**
	* @name Writer stuff
	* @{
	*/
	
	/** Write handler. */
	write_handler: yaml_write_handler_t,

	/** A pointer for passing to the write handler. */
	write_handler_data: rawptr,

	output: struct #raw_union {
		_string: struct {
			/** The buffer pointer. */
			buffer: ^u8,

			/** The buffer size. */
			size: c.size_t,

			/** The number of written bytes. */
			size_written: ^c.size_t,
		},

		/** File output data. */
		file: ^libc.FILE,
	},

	buffer: struct {
		/** The beginning of the buffer. */
		start: ^yaml_char_t,

		/** The end of the buffer. */
		end: ^yaml_char_t,

		/** The current position of the buffer. */
		pointer: ^yaml_char_t,

		/** The last filled position of the buffer. */
		last: ^yaml_char_t,
	},

	raw_buffer: struct {
		/** The beginning of the buffer. */
		start: ^u8,

		/** The end of the buffer. */
		end: ^u8,

		/** The current position of the buffer. */
		pointer: ^u8,

		/** The last filled position of the buffer. */
		last: ^u8,
	},

	/** The stream encoding. */
	encoding: yaml_encoding_t,

	/**
	* @}
	*/
	
	/**
	* @name Emitter stuff
	* @{
	*/
	
	/** If the output is in the canonical style? */
	canonical: i32,

	/** The number of indentation spaces. */
	best_indent: i32,

	/** The preferred width of the output lines. */
	best_width: i32,

	/** Allow unescaped non-ASCII characters? */
	unicode: i32,

	/** The preferred line break. */
	line_break: yaml_break_t,

	states: struct {
		/** The beginning of the stack. */
		start: ^yaml_emitter_state_t,

		/** The end of the stack. */
		end: ^yaml_emitter_state_t,

		/** The top of the stack. */
		top: ^yaml_emitter_state_t,
	},

	/** The current emitter state. */
	state: yaml_emitter_state_t,

	events: struct {
		/** The beginning of the event queue. */
		start: ^yaml_event_t,

		/** The end of the event queue. */
		end: ^yaml_event_t,

		/** The head of the event queue. */
		head: ^yaml_event_t,

		/** The tail of the event queue. */
		tail: ^yaml_event_t,
	},

	indents: struct {
		/** The beginning of the stack. */
		start: ^i32,

		/** The end of the stack. */
		end: ^i32,

		/** The top of the stack. */
		top: ^i32,
	},

	tag_directives: struct {
		/** The beginning of the list. */
		start: ^yaml_tag_directive_t,

		/** The end of the list. */
		end: ^yaml_tag_directive_t,

		/** The top of the list. */
		top: ^yaml_tag_directive_t,
	},

	/** The current indentation level. */
	indent: i32,

	/** The current flow level. */
	flow_level: i32,

	/** Is it the document root context? */
	root_context: i32,

	/** Is it a sequence context? */
	sequence_context: i32,

	/** Is it a mapping context? */
	mapping_context: i32,

	/** Is it a simple mapping key context? */
	simple_key_context: i32,

	/** The current line. */
	line: i32,

	/** The current column. */
	column: i32,

	/** If the last character was a whitespace? */
	whitespace: i32,

	/** If the last character was an indentation character (' ', '-', '?', ':')? */
	indention: i32,

	/** If an explicit document end is required? */
	open_ended: i32,

	anchor_data: struct {
		/** The anchor value. */
		anchor: ^yaml_char_t,

		/** The anchor length. */
		anchor_length: c.size_t,

		/** Is it an alias? */
		alias: i32,
	},

	tag_data: struct {
		/** The tag handle. */
		handle: ^yaml_char_t,

		/** The tag handle length. */
		handle_length: c.size_t,

		/** The tag suffix. */
		suffix: ^yaml_char_t,

		/** The tag suffix length. */
		suffix_length: c.size_t,
	},

	scalar_data: struct {
		/** The scalar value. */
		value: ^yaml_char_t,

		/** The scalar length. */
		length: c.size_t,

		/** Does the scalar contain line breaks? */
		multiline: i32,

		/** Can the scalar be expressed in the flow plain style? */
		flow_plain_allowed: i32,

		/** Can the scalar be expressed in the block plain style? */
		block_plain_allowed: i32,

		/** Can the scalar be expressed in the single quoted style? */
		single_quoted_allowed: i32,

		/** Can the scalar be expressed in the literal or folded styles? */
		block_allowed: i32,

		/** The output style. */
		style: yaml_scalar_style_t,
	},

	/**
	* @}
	*/
	
	/**
	* @name Dumper stuff
	* @{
	*/
	
	/** If the stream was already opened? */
	opened: i32,

	/** If the stream was already closed? */
	closed: i32,

	/** The information associated with the document nodes. */
	anchors: ^yaml_anchors_t,

	/** The last assigned anchor id. */
	last_anchor_id: i32,

	/** The currently emitted document. */
	document: ^yaml_document_t,
}

/**
* The emitter structure.
*
* All members are internal.  Manage the structure using the @c yaml_emitter_
* family of functions.
*/
yaml_emitter_t :: yaml_emitter_s

@(default_calling_convention="c")
foreign lib {
	/**
	* Initialize an emitter.
	*
	* This function creates a new emitter object.  An application is responsible
	* for destroying the object using the yaml_emitter_delete() function.
	*
	* @param[out]      emitter     An empty parser object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_emitter_initialize :: proc(emitter: ^yaml_emitter_t) -> i32 ---

	/**
	* Destroy an emitter.
	*
	* @param[in,out]   emitter     An emitter object.
	*/
	yaml_emitter_delete :: proc(emitter: ^yaml_emitter_t) ---

	/**
	* Set a string output.
	*
	* The emitter will write the output characters to the @a output buffer of the
	* size @a size.  The emitter will set @a size_written to the number of written
	* bytes.  If the buffer is smaller than required, the emitter produces the
	* YAML_WRITE_ERROR error.
	*
	* @param[in,out]   emitter         An emitter object.
	* @param[in]       output          An output buffer.
	* @param[in]       size            The buffer size.
	* @param[in]       size_written    The pointer to save the number of written
	*                                  bytes.
	*/
	yaml_emitter_set_output_string :: proc(emitter: ^yaml_emitter_t, output: ^u8, size: c.size_t, size_written: ^c.size_t) ---

	/**
	* Set a file output.
	*
	* @a file should be a file object open for writing.  The application is
	* responsible for closing the @a file.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in]       file        An open file.
	*/
	yaml_emitter_set_output_file :: proc(emitter: ^yaml_emitter_t, file: ^libc.FILE) ---

	/**
	* Set a generic output handler.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in]       handler     A write handler.
	* @param[in]       data        Any application data for passing to the write
	*                              handler.
	*/
	yaml_emitter_set_output :: proc(emitter: ^yaml_emitter_t, handler: yaml_write_handler_t, data: rawptr) ---

	/**
	* Set the output encoding.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in]       encoding    The output encoding.
	*/
	yaml_emitter_set_encoding :: proc(emitter: ^yaml_emitter_t, encoding: yaml_encoding_t) ---

	/**
	* Set if the output should be in the "canonical" format as in the YAML
	* specification.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in]       canonical   If the output is canonical.
	*/
	yaml_emitter_set_canonical :: proc(emitter: ^yaml_emitter_t, canonical: i32) ---

	/**
	* Set the indentation increment.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in]       indent      The indentation increment (1 < . < 10).
	*/
	yaml_emitter_set_indent :: proc(emitter: ^yaml_emitter_t, indent: i32) ---

	/**
	* Set the preferred line width. @c -1 means unlimited.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in]       width       The preferred line width.
	*/
	yaml_emitter_set_width :: proc(emitter: ^yaml_emitter_t, width: i32) ---

	/**
	* Set if unescaped non-ASCII characters are allowed.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in]       unicode     If unescaped Unicode characters are allowed.
	*/
	yaml_emitter_set_unicode :: proc(emitter: ^yaml_emitter_t, unicode: i32) ---

	/**
	* Set the preferred line break.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in]       line_break  The preferred line break.
	*/
	yaml_emitter_set_break :: proc(emitter: ^yaml_emitter_t, line_break: yaml_break_t) ---

	/**
	* Emit an event.
	*
	* The event object may be generated using the yaml_parser_parse() function.
	* The emitter takes the responsibility for the event object and destroys its
	* content after it is emitted. The event object is destroyed even if the
	* function fails.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in,out]   event       An event object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_emitter_emit :: proc(emitter: ^yaml_emitter_t, event: ^yaml_event_t) -> i32 ---

	/**
	* Start a YAML stream.
	*
	* This function should be used before yaml_emitter_dump() is called.
	*
	* @param[in,out]   emitter     An emitter object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_emitter_open :: proc(emitter: ^yaml_emitter_t) -> i32 ---

	/**
	* Finish a YAML stream.
	*
	* This function should be used after yaml_emitter_dump() is called.
	*
	* @param[in,out]   emitter     An emitter object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_emitter_close :: proc(emitter: ^yaml_emitter_t) -> i32 ---

	/**
	* Emit a YAML document.
	*
	* The document object may be generated using the yaml_parser_load() function
	* or the yaml_document_initialize() function.  The emitter takes the
	* responsibility for the document object and destroys its content after
	* it is emitted. The document object is destroyed even if the function fails.
	*
	* @param[in,out]   emitter     An emitter object.
	* @param[in,out]   document    A document object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_emitter_dump :: proc(emitter: ^yaml_emitter_t, document: ^yaml_document_t) -> i32 ---

	/**
	* Flush the accumulated characters to the output.
	*
	* @param[in,out]   emitter     An emitter object.
	*
	* @returns @c 1 if the function succeeded, @c 0 on error.
	*/
	yaml_emitter_flush :: proc(emitter: ^yaml_emitter_t) -> i32 ---
}

