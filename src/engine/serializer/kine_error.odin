package serializer

import "core:fmt"
import "core:strings"

Error_Kind :: enum {
	None,

	Invalid_Argument,

	Truncated,

	Bad_Magic,

	Unsupported_Version,

	Malformed_Record,

	// The stream decoded cleanly but had bytes left over, which means the reader
	// and the writer disagree about the layout.
	Trailing_Bytes,

	// The stream names something this build does not have: an unknown class, an
	// unknown userdata datatype, or an unknown value tag.
	Unknown_Class,
	Unknown_Datatype,
	Unknown_Value_Tag,

	// A property getter raised while the writer was reading a value. The property
	// is left out of the stream and the rest of the save continues.
	Property_Read_Failed,

	// The runtime refused a value the stream asked for: a setter raised on a
	// property, or an attribute could not be stored. A rejected property is
	// reported and skipped; a rejected attribute ends the load.
	Property_Rejected,

	// A property held a value the format has no record for, so it was skipped.
	Unsupported_Value,

	// The class exists but the object could not be constructed.
	Object_Create_Failed,

	// Asset table problems: too many entries, an entry too large, a total over
	// the budget, a blob that was already claimed, or bytes that would not
	// register.
	Asset_Count_Exceeded,
	Asset_Size_Exceeded,
	Asset_Total_Exceeded,
	Asset_Missing,
	Asset_Corrupt,

	// Terrain section problems: a short header, a grid whose voxel size or iso
	// level is unusable, a cell count over the cap or larger than the bytes
	// present, or a coordinate outside the supported range.
	Terrain_Truncated,
	Terrain_Invalid_Grid,
	Terrain_Cell_Count_Exceeded,
	Terrain_Cell_Out_Of_Range,

	// The container could not be read or written.
	File_Read_Failed,
	File_Write_Failed,

	// The zstd framing could not be produced or expanded, or a frame claimed a
	// decompressed size this build refuses to allocate.
	Compress_Failed,
	Decompress_Failed,
	Stream_Too_Large,

	// The write side lost a record it could not explain. Reported rather than
	// hidden, because it means the stream is missing something the tree held.
	Internal,
}

// Error is one failure. message is owned by the Error and must be released with
// Error_Delete; offset is the byte position in the stream where the failure was
// detected, or -1 for a failure that never touched the bytes (a file that could
// not be opened, say).
Error :: struct {
	kind:    Error_Kind,
	offset:  int,
	message: string,
}

// Error_None is the success value. It owns nothing, so copying it around and
// deleting it are both safe.
Error_None :: Error {
	kind    = .None,
	offset  = -1,
	message = "",
}

// Error_Is_None reports whether err means success.
Error_Is_None :: proc(err: Error) -> bool {
	return err.kind == .None
}

// error_tprintf formats into an owned string. fmt.tprintf allocates from
// context.temp_allocator, whose results must not be freed, so every message an
// Error or a caller owns is cloned out of here before it is stored.
error_tprintf :: proc(format: string, args: ..any) -> string {
	return strings.clone(fmt.tprintf(format, ..args))
}

// Error_Make builds a failure with a freshly formatted detail.
Error_Make :: proc(kind: Error_Kind, offset: int, format: string, args: ..any) -> Error {
	return Error {
		kind    = kind,
		offset  = offset,
		message = error_tprintf(format, ..args),
	}
}

// Error_Set records a failure unless one is already recorded. The first failure
// wins on purpose: it comes from the record that actually went wrong, and an
// outer frame repeating itself would only bury that detail behind less useful
// news about its own record.
Error_Set :: proc(err: ^Error, kind: Error_Kind, offset: int, format: string, args: ..any) {
	if err == nil || err.kind != .None {
		return
	}
	err.kind = kind
	err.offset = offset
	err.message = error_tprintf(format, ..args)
}

// Error_Context prepends where a failure happened to a detail that is already
// recorded. It is how a low level report like "stream ended 4 bytes early"
// acquires the context that makes it actionable, such as the instance, property,
// or section it was reading at the time.
Error_Context :: proc(err: ^Error, format: string, args: ..any) {
	if err == nil || err.message == "" {
		return
	}
	detail := fmt.tprintf(format, ..args)
	combined := error_tprintf("%s: %s", detail, err.message)
	delete(err.message)
	err.message = combined
}

// Error_Delete releases the message a failure allocated. It is safe on
// Error_None, on a nil pointer, and on an Error that has already been deleted.
Error_Delete :: proc(err: ^Error) {
	if err == nil {
		return
	}
	delete(err.message)
	err.message = ""
	err.kind = .None
	err.offset = -1
}

// Error_Take moves the failure out of err, leaving err as Error_None. Used when
// the failure has to outlive the struct it came from, such as one stored on a
// Reader whose own cleanup would otherwise free the caller's message.
Error_Take :: proc(err: ^Error) -> Error {
	if err == nil || err.kind == .None {
		return Error_None
	}
	taken := Error {
		kind    = err.kind,
		offset  = err.offset,
		message = err.message,
	}
	err.message = ""
	err.kind = .None
	err.offset = -1
	return taken
}

// Error_Kind_Name is the stable label for a kind, used when rendering an error
// so the category survives into a log line or an exception message.
Error_Kind_Name :: proc(kind: Error_Kind) -> string {
	switch kind {
	case .None:
		return "no error"
	case .Invalid_Argument:
		return "invalid argument"
	case .Truncated:
		return "truncated stream"
	case .Bad_Magic:
		return "bad magic"
	case .Unsupported_Version:
		return "unsupported version"
	case .Malformed_Record:
		return "malformed record"
	case .Trailing_Bytes:
		return "trailing bytes"
	case .Unknown_Class:
		return "unknown class"
	case .Unknown_Datatype:
		return "unknown datatype"
	case .Unknown_Value_Tag:
		return "unknown value tag"
	case .Property_Read_Failed:
		return "property read failed"
	case .Property_Rejected:
		return "property rejected"
	case .Unsupported_Value:
		return "unsupported value"
	case .Object_Create_Failed:
		return "object create failed"
	case .Asset_Count_Exceeded:
		return "asset count exceeded"
	case .Asset_Size_Exceeded:
		return "asset size exceeded"
	case .Asset_Total_Exceeded:
		return "asset total exceeded"
	case .Asset_Missing:
		return "asset missing"
	case .Asset_Corrupt:
		return "asset corrupt"
	case .Terrain_Truncated:
		return "terrain truncated"
	case .Terrain_Invalid_Grid:
		return "terrain invalid grid"
	case .Terrain_Cell_Count_Exceeded:
		return "terrain cell count exceeded"
	case .Terrain_Cell_Out_Of_Range:
		return "terrain cell out of range"
	case .File_Read_Failed:
		return "file read failed"
	case .File_Write_Failed:
		return "file write failed"
	case .Compress_Failed:
		return "compress failed"
	case .Decompress_Failed:
		return "decompress failed"
	case .Stream_Too_Large:
		return "stream too large"
	case .Internal:
		return "internal"
	}
	return "unknown"
}

// Error_String renders an error as one line for a log or an exception message.
// The result is owned by the caller.
Error_String :: proc(err: Error) -> string {
	if err.kind == .None {
		return strings.clone("no error")
	}
	if err.offset >= 0 {
		return error_tprintf(
			"kine %s at byte %d: %s",
			Error_Kind_Name(err.kind),
			err.offset,
			err.message,
		)
	}
	return error_tprintf("kine %s: %s", Error_Kind_Name(err.kind), err.message)
}

// Error_Print writes an error to stderr with an optional prefix. A successful
// Error prints nothing, so a caller does not have to guard the call.
Error_Print :: proc(err: Error, prefix: string = "") {
	if err.kind == .None {
		return
	}
	message := Error_String(err)
	defer delete(message)
	if prefix == "" {
		fmt.eprintf("%s\n", message)
		return
	}
	fmt.eprintf("%s%s\n", prefix, message)
}

// ---------------------------------------------------------------------------
// Reader and Writer plumbing
// ---------------------------------------------------------------------------

// reader_fail records why the stream could not be decoded and reports failure.
// The offset is the reader's cursor, which is by construction the record that
// went wrong, so a call site only has to name the record in the message.
reader_fail :: proc(r: ^Reader, kind: Error_Kind, format: string, args: ..any) -> bool {
	if r != nil {
		Error_Set(&r.err, kind, r.pos, format, ..args)
	}
	return false
}

// reader_fail_at is reader_fail for a position the caller has already read past,
// used when the blame belongs to an earlier byte than the cursor.
reader_fail_at :: proc(r: ^Reader, kind: Error_Kind, offset: int, format: string, args: ..any) -> bool {
	if r != nil {
		Error_Set(&r.err, kind, offset, format, ..args)
	}
	return false
}

// reader_context names the record a recorded failure was found in, without
// replacing the detail the record itself reported.
reader_context :: proc(r: ^Reader, format: string, args: ..any) -> bool {
	if r != nil {
		Error_Context(&r.err, format, ..args)
	}
	return false
}

// reader_take moves the reader's failure out to be returned, so the reader's own
// cleanup does not free a message the caller now owns. A decode that failed
// without recording anything is itself a bug, and is reported rather than
// passed off as success.
reader_take :: proc(r: ^Reader) -> Error {
	if r == nil {
		return Error_Make(.Internal, -1, "the reader is nil")
	}
	if r.err.kind == .None {
		return Error_Make(
			.Internal,
			r.pos,
			"the stream could not be decoded at byte %d and no reason was recorded",
			r.pos,
		)
	}
	return Error_Take(&r.err)
}

// writer_skip records why a record is being left out of the stream. It never
// raises: dropping one property or one subtree leaves the rest of the file
// valid, so the caller recovers and keeps saving. The call site that recovered
// takes the detail with writer_take_warning and logs it, which is what turns a
// silently incomplete map into one the author hears about.
//
// The first reason wins, because it comes from the value that actually could not
// be encoded and is more specific than anything an outer frame could add.
writer_skip :: proc(w: ^Writer, format: string, args: ..any) -> bool {
	if w == nil {
		return false
	}
	if w.warn == "" {
		w.warn = error_tprintf(format, ..args)
	}
	return false
}

// writer_skip_context prepends where a skipped record sits to a reason already
// recorded, leaving the reason itself intact. Outer frames use this so the
// reported detail ends up naming the whole path, such as 'Part "Body" property
// MeshId: the value has Lua type thread'.
writer_skip_context :: proc(w: ^Writer, format: string, args: ..any) -> bool {
	if w == nil || w.warn == "" {
		return false
	}
	detail := fmt.tprintf(format, ..args)
	combined := error_tprintf("%s: %s", detail, w.warn)
	delete(w.warn)
	w.warn = combined
	return false
}

// writer_take_warning returns the pending skip detail and clears it. The result
// is owned by the caller.
writer_take_warning :: proc(w: ^Writer) -> string {
	if w == nil || w.warn == "" {
		return ""
	}
	warning := w.warn
	w.warn = ""
	return warning
}

// writer_discard_warning drops a pending skip detail without reporting it, for
// the paths that treat the condition as ordinary rather than as news.
writer_discard_warning :: proc(w: ^Writer) {
	if w == nil {
		return
	}
	delete(w.warn)
	w.warn = ""
}

// writer_error turns a pending skip detail into a fatal Error, for the write
// paths that cannot recover.
writer_error :: proc(w: ^Writer, kind: Error_Kind, format: string, args: ..any) -> Error {
	detail := fmt.tprintf(format, ..args)
	warning := writer_take_warning(w)
	defer delete(warning)
	if warning == "" {
		return Error_Make(kind, -1, "%s", detail)
	}
	return Error_Make(kind, -1, "%s: %s", detail, warning)
}