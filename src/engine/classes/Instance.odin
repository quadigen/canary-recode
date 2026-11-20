package classes

Instance_Class := Class_Info {
	name   = "Instance",
	parent = &Object_Class,
}

Instance :: struct {
	using object: Object,
}

Instance_Init :: proc() -> Instance {
	return Instance{object = Object_Init(&Instance_Class, "Instance")}
}

instance_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	instance := new(Instance)
	instance^ = Instance_Init()
	return &instance.object
}

instance_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Instance)object)
}

instance_clone :: proc(source: ^Object, destination: ^Object) {
	// No extra properties
}

INSTANCE_PROPERTIES := []string {
	"Name",
	"ClassName",
	"Parent",
	"Archivable",
	"CanReplicate",
	"ReplicationGroup",
	"ReplicationMode",
	"NetworkId",
	"UniqueId",
	"Capabilities",
	"Sandboxed",
	"IsInSandbox",
}

INSTANCE_METHODS := []string {
	"Clone",
	"Destroy",
	"ClearAllChildren",
	"AddTag",
	"RemoveTag",
	"HasTag",
	"GetTags",
	"FindFirstChild",
	"FindFirstChildOfClass",
	"FindFirstChildWhichIsA",
	"FindFirstDescendant",
	"FindFirstAncestor",
	"FindFirstAncestorOfClass",
	"FindFirstAncestorWhichIsA",
	"WaitForChild",
	"WaitForChildOfClass",
	"GetChildren",
	"GetDescendants",
	"GetFullName",
	"GetProperties",
	"IsA",
	"IsAncestorOf",
	"IsDescendantOf",
	"GetAttribute",
	"GetAttributes",
	"GetAttributeChangedSignal",
	"SetAttribute",
	"GetPropertyChangedSignal",
}

INSTANCE_EVENTS := []string {
	"Changed",
	"AttributeChanged",
	"ChildAdded",
	"ChildRemoved",
	"DescendantAdded",
	"DescendantRemoving",
	"AncestryChanged",
	"Destroying",
}

Register_Instance :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Instance_Class,
		instance_construct,
		instance_destroy,
		clone = instance_clone,
		properties = INSTANCE_PROPERTIES,
		methods = INSTANCE_METHODS,
		events = INSTANCE_EVENTS,
	)
}
