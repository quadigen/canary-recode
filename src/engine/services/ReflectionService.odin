package services

// wire:service global="ReflectionService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ReflectionService_Class := classes.Class_Info{
	name   = "ReflectionService",
	parent = &Service_Class,
}

ReflectionService :: struct {
	using service: Service,
}

Reflection_Member_Kind :: enum {
	Method,
	Event,
	Property,
}

Reflection_Filter :: struct {
	security:          datatypes.SecurityCapabilities,
	is_a:              string,
	exclude_display:   bool,
	exclude_inherited: bool,
}

reflection_read_filter :: proc(
	L: ^vm.State,
	index: int,
	datatype_registry: ^datatypes.Registry,
) -> Reflection_Filter {
	filter := Reflection_Filter{
		security = datatypes.SecurityCapabilities_From_VM(
			vm.GetThreadSecurityCapabilities(L),
		),
	}

	if !vm.IsTable(L, index) {
		return filter
	}

	vm.GetField(L, index, "Security")
	if vm.IsUserdataType(L, -1, &datatype_registry.security_capabilities) {
		filter.security = (cast(^datatypes.SecurityCapabilities)vm.UserdataValue(L, -1))^
	}
	vm.Pop(L)

	vm.GetField(L, index, "IsA")
	if vm.IsString(L, -1) {
		filter.is_a = vm.ArgString(L, -1)
	}
	vm.Pop(L)

	vm.GetField(L, index, "ExcludeDisplay")
	if vm.IsBoolean(L, -1) {
		filter.exclude_display = vm.ArgBoolean(L, -1)
	}
	vm.Pop(L)

	vm.GetField(L, index, "ExcludeInherited")
	if vm.IsBoolean(L, -1) {
		filter.exclude_inherited = vm.ArgBoolean(L, -1)
	}
	vm.Pop(L)

	return filter
}

reflection_class_is_a :: proc(
	registry: ^classes.Registry,
	class_name: string,
	base: string,
) -> bool {
	if base == "" {
		return true
	}

	descriptor := classes.Find_Class(registry, class_name)
	if descriptor == nil {
		return false
	}

	class := descriptor.info
	for class != nil {
		if class.name == base {
			return true
		}
		class = class.parent
	}

	return false
}

// reflection_push_permit writes one SecurityCapabilities entry into a Permits
// table, or leaves the field absent when the filter's capabilities do not cover
// the requirement. Roblox omits a Permit entirely in that case rather than
// reporting an empty requirement.
reflection_push_permit :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	permits_index: int,
	field: string,
	requirement: vm.Security_Requirement,
	filter: Reflection_Filter,
) {
	caps := datatypes.SecurityCapabilities_From_VM(requirement.capabilities)
	if !datatypes.SecurityCapabilities_Contains(filter.security, caps) {
		return
	}

	datatypes.Push_SecurityCapabilities(L, datatype_registry, caps)
	vm.SetField(L, permits_index, field)
}

// reflection_push_display writes the Studio display block unless the filter
// asked for it to be excluded. Category defaults to "General" because the engine
// does not track per-class categories.
reflection_push_display :: proc(
	L: ^vm.State,
	table_index: int,
	filter: Reflection_Filter,
) {
	if filter.exclude_display {
		return
	}

	vm.NewTable(L, 0, 1)
	vm.PushString(L, "General")
	vm.SetField(L, -2, "Category")
	vm.SetField(L, table_index, "Display")
}

// reflection_class_visible reports whether the filter's capabilities cover
// whatever is required to reach `descriptor`. Services carry a GetService
// requirement, so a script without that capability cannot see the class at all;
// ordinary classes are always visible.
reflection_class_visible :: proc(
	services_registry: ^Registry,
	registry: ^classes.Registry,
	descriptor: ^classes.Class_Descriptor,
	filter: Reflection_Filter,
) -> bool {
	if registry == nil || descriptor == nil {
		return false
	}

	service := Find_Service(services_registry, descriptor.info.name)
	if service == nil {
		return true
	}

	required := datatypes.SecurityCapabilities_From_VM(service.security.capabilities)
	return datatypes.SecurityCapabilities_Contains(filter.security, required)
}

// reflection_push_class builds one ReflectedClass dictionary.
reflection_push_class :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	services_registry: ^Registry,
	registry: ^classes.Registry,
	descriptor: ^classes.Class_Descriptor,
	filter: Reflection_Filter,
) {
	vm.NewTable(L, 0, 6)

	vm.PushString(L, descriptor.info.name)
	vm.SetField(L, -2, "Name")

	// The engine has no per-class serialized flag, so this follows the same rule
	// the place serializer uses: every registered class can be written to disk.
	vm.PushBoolean(L, true)
	vm.SetField(L, -2, "Serialized")

	if descriptor.info.parent != nil {
		vm.PushString(L, descriptor.info.parent.name)
	} else {
		vm.PushNil(L)
	}
	vm.SetField(L, -2, "Superclass")

	// Subclasses lists the direct children in the class hierarchy.
	subclasses: [dynamic]string
	for other in registry.classes {
		if other.info.parent == descriptor.info {
			append(&subclasses, other.info.name)
		}
	}

	vm.NewTable(L, len(subclasses))
	for subclass, index in subclasses {
		vm.PushString(L, subclass)
		vm.SetArrayValue(L, -2, index+1)
	}
	delete(subclasses)
	vm.SetField(L, -2, "Subclasses")

	vm.NewTable(L, 0, 2)
	permits := vm.StackTop(L)

	// GetService only applies to classes registered as services, and reports the
	// capabilities a script needs before `game:GetService` will hand it over.
	if service := Find_Service(services_registry, descriptor.info.name);
	   service != nil {
		reflection_push_permit(
			L,
			datatype_registry,
			permits,
			"GetService",
			service.security,
			filter,
		)
	}

	// New applies to classes a script may construct through Instance.new().
	if descriptor.creatable {
		reflection_push_permit(
			L,
			datatype_registry,
			permits,
			"New",
			vm.SECURITY_REQUIREMENT_NONE,
			filter,
		)
	}

	vm.SetField(L, -2, "Permits")

	reflection_push_display(L, -2, filter)
}

// reflection_push_parameters writes the Parameters list shared by reflected
// methods and events. The engine does not track parameter names or signatures,
// so a single entry describes the member using its own name and a generic type.
reflection_push_parameters :: proc(L: ^vm.State, name: string) {
	vm.NewTable(L, 1)

	vm.NewTable(L, 0, 2)
	vm.PushString(L, name)
	vm.SetField(L, -2, "Name")
	vm.PushString(L, "any")
	vm.SetField(L, -2, "Type")
	vm.SetArrayValue(L, -3, 1)
}

// reflection_push_member renders a single ReflectedMethod/ReflectedEvent/
// ReflectedProperty dictionary. Security requirements come from the class's
// member_security rules so a restricted member is reported as restricted.
reflection_push_member :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	descriptor: ^classes.Class_Descriptor,
	entry: classes.Class_Member_Entry,
	kind: Reflection_Member_Kind,
	filter: Reflection_Filter,
) {
	vm.NewTable(L, 0, 6)

	vm.PushString(L, entry.name)
	vm.SetField(L, -2, "Name")

	vm.PushString(L, entry.owner)
	vm.SetField(L, -2, "Owner")

	switch kind {
	case .Method:
		reflection_push_parameters(L, entry.name)
		vm.SetField(L, -2, "Parameters")

		vm.PushString(L, "any")
		vm.SetField(L, -2, "ReturnType")

		// The engine has no yielding-method metadata, so this is reported
		// conservatively rather than guessed per method.
		vm.PushBoolean(L, false)
		vm.SetField(L, -2, "CanYield")

		vm.NewTable(L, 0, 2)
		permits := vm.StackTop(L)
		reflection_push_permit(
			L,
			datatype_registry,
			permits,
			"Call",
			classes.Member_Requirement(descriptor, entry.name, .Call),
			filter,
		)
		reflection_push_permit(
			L,
			datatype_registry,
			permits,
			"CallParallel",
			classes.Member_Requirement(descriptor, entry.name, .Call),
			filter,
		)
		vm.SetField(L, -2, "Permits")

	case .Event:
		reflection_push_parameters(L, entry.name)
		vm.SetField(L, -2, "Parameters")

		vm.NewTable(L, 0, 1)
		permits := vm.StackTop(L)
		reflection_push_permit(
			L,
			datatype_registry,
			permits,
			"Listen",
			classes.Member_Requirement(descriptor, entry.name, .Call),
			filter,
		)
		vm.SetField(L, -2, "Permits")

	case .Property:
		vm.PushBoolean(L, true)
		vm.SetField(L, -2, "Serialized")

		vm.PushString(L, "any")
		vm.SetField(L, -2, "Type")

		// ContentType only applies to asset-backed properties, which this
		// engine does not model, so the field is present but unset.
		vm.PushNil(L)
		vm.SetField(L, -2, "ContentType")

		read_requirement := classes.Member_Requirement(descriptor, entry.name, .Read)
		write_requirement := classes.Member_Requirement(descriptor, entry.name, .Write)

		vm.NewTable(L, 0, 4)
		permits := vm.StackTop(L)
		reflection_push_permit(L, datatype_registry, permits, "Read", read_requirement, filter)
		reflection_push_permit(L, datatype_registry, permits, "ReadParallel", read_requirement, filter)
		reflection_push_permit(L, datatype_registry, permits, "Write", write_requirement, filter)
		reflection_push_permit(L, datatype_registry, permits, "WriteParallel", write_requirement, filter)
		vm.SetField(L, -2, "Permits")
	}

	reflection_push_display(L, -2, filter)
}

// reflection_push_members renders the member list shared by
// GetPropertiesOfClass, GetMethodsOfClass, and GetEventsOfClass.
reflection_push_members :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	registry: ^classes.Registry,
	class_name: string,
	list: classes.Class_Member_List,
	kind: Reflection_Member_Kind,
	filter: Reflection_Filter,
) {
	entries := classes.Collect_Class_Members(registry, class_name, list)
	defer delete(entries)

	vm.NewTable(L, len(entries))

	output := 1
	for entry in entries {
		// ExcludeInherited drops everything the class did not declare itself.
		if filter.exclude_inherited && entry.owner != class_name {
			continue
		}

		descriptor := classes.Find_Class(registry, entry.owner)
		if descriptor == nil {
			continue
		}

		reflection_push_member(L, datatype_registry, descriptor, entry, kind, filter)
		vm.SetArrayValue(L, -2, output)
		output += 1
	}
}

// reflection_registries resolves the service and class registries a live
// ReflectionService reads from. Both hang off the DataModel the service was
// constructed against, so a detached service reports nil instead of crashing.
reflection_registries :: proc(
	service: ^ReflectionService,
) -> (^Registry, ^classes.Registry) {
	if service == nil ||
	   service.data_model == nil ||
	   service.data_model.registry == nil {
		return nil, nil
	}

	registry := service.data_model.registry
	return registry, registry.classes
}

reflection_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ReflectionService)
	service.service = Service_Init(
		&ReflectionService_Class,
		"ReflectionService",
		data_model,
	)
	return &service.object
}

reflection_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetClass",
	     "GetClasses",
	     "GetEventsOfClass",
	     "GetMethodsOfClass",
	     "GetPropertiesOfClass":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}

	return true
}

reflection_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^ReflectionService)object
	services_registry, class_registry := reflection_registries(service)
	if class_registry == nil {
		return vm.RaiseError(L, "ReflectionService is not attached to a DataModel"), true
	}

	switch method {
	case "GetClass":
		class_name := vm.ArgString(L, 2)
		filter := reflection_read_filter(L, 3, datatype_registry)

		descriptor := classes.Find_Class(class_registry, class_name)
		// An unknown class, a class filtered out by IsA, and a class the caller
		// lacks the capabilities to reach are all reported as "no such class",
		// which is what the nil return documents.
		if descriptor == nil ||
		   !reflection_class_is_a(class_registry, class_name, filter.is_a) ||
		   !reflection_class_visible(
			services_registry,
			class_registry,
			descriptor,
			filter,
		   ) {
			vm.PushNil(L)
			return 1, true
		}

		reflection_push_class(
			L,
			datatype_registry,
			services_registry,
			class_registry,
			descriptor,
			filter,
		)
		return 1, true

	case "GetClasses":
		filter := reflection_read_filter(L, 2, datatype_registry)

		matching: [dynamic]^classes.Class_Descriptor
		for descriptor in class_registry.classes {
			if reflection_class_is_a(class_registry, descriptor.info.name, filter.is_a) &&
			   reflection_class_visible(
				services_registry,
				class_registry,
				descriptor,
				filter,
			   ) {
				append(&matching, descriptor)
			}
		}
		defer delete(matching)

		vm.NewTable(L, len(matching))
		for descriptor, index in matching {
			reflection_push_class(
				L,
				datatype_registry,
				services_registry,
				class_registry,
				descriptor,
				filter,
			)
			vm.SetArrayValue(L, -2, index+1)
		}
		return 1, true

	case "GetPropertiesOfClass",
	     "GetMethodsOfClass",
	     "GetEventsOfClass":
		list := classes.Class_Member_List.Properties
		kind := Reflection_Member_Kind.Property
		switch method {
		case "GetMethodsOfClass":
			list = .Methods
			kind = .Method
		case "GetEventsOfClass":
			list = .Events
			kind = .Event
		}

		class_name := vm.ArgString(L, 2)
		filter := reflection_read_filter(L, 3, datatype_registry)

		descriptor := classes.Find_Class(class_registry, class_name)
		if descriptor == nil ||
		   !reflection_class_visible(
			services_registry,
			class_registry,
			descriptor,
			filter,
		   ) {
			vm.PushNil(L)
			return 1, true
		}

		reflection_push_members(
			L,
			datatype_registry,
			class_registry,
			class_name,
			list,
			kind,
			filter,
		)
		return 1, true
	}

	return 0, false
}

reflection_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^ReflectionService)object)
}

Register_ReflectionService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ReflectionService_Class,
		reflection_service_construct,
		reflection_service_destroy,
		creatable = false,
		get = reflection_service_get,
		namecall = reflection_service_namecall,
	)
}
