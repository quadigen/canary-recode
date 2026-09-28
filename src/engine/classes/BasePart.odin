package classes

// BasePart is the abstract parent of every solid-geometry class. It exists for
// the class hierarchy itself, not for any data.
//
// `IsA` walks the parent chain comparing names, and the chain used to go
// straight from Instance to Part, so it never found a "BasePart" to match and
// answered false for every Part in the world. That made the single most common
// test in part-oriented gameplay code --
//
//     for _, object in map:GetDescendants() do
//         if object:IsA("BasePart") then ...
//
// -- silently select nothing, with no error to explain why: the traversal
// worked, the filter simply never matched.
//
// Part and MeshPart declare the physical fields themselves, so this class adds
// no data and no behaviour. It is not creatable, matching Roblox, where
// BasePart is an abstract base you can only test for.
BasePart_Class := Class_Info{
	name   = "BasePart",
	parent = &Instance_Class,
}

BasePart :: struct {
	using object: Object,
}

base_part_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	part := new(BasePart)
	part^ = BasePart{object = Object_Init(&BasePart_Class, "BasePart")}
	return &part.object
}

base_part_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^BasePart)object)
}

base_part_clone :: proc(source: ^Object, destination: ^Object) {
	// No properties of its own to copy.
}

Register_BasePart :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BasePart_Class,
		base_part_construct,
		base_part_destroy,
		// Abstract: Instance.new("BasePart") is not a thing, exactly as in
		// Roblox. Anything you can actually place is a Part or a MeshPart.
		creatable = false,
		clone      = base_part_clone,
	)
}