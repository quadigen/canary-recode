# Engine wiring

Run `just wire` (only supported for Windows) after adding an engine type. The command discovers declarations,
updates the generated regions in the registries, and refreshes the Luau enum
registry, then type-checks the engine. `just wire-check` fails when generated
wiring is stale without changing files.

## Classes

Put the class in `src/engine/classes` and expose this registration procedure:

```odin
Register_MyClass :: proc(registry: ^Registry) {
	Register_Class(registry, &MyClass_Class, my_class_construct, my_class_destroy)
}
```

## Services

Put the service in `src/engine/services`, derive its `Class_Info` directly from
`Service_Class`, and expose `Register_MyService_Class(registry: ^classes.Registry)`.
The service becomes available through `game:GetService("MyService")` after wiring.

Add this optional file-level annotation when the service also needs a Luau global:

```odin
// wire:service global="myService"
```

## Datatypes

Put the Luau binding in `src/engine/datatypes` and expose both procedures:

```odin
MyType_Luau_Binding :: proc() -> vm.Userdata_Binding
MyType_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding)
```

The generated registry field is the snake-case type name, such as
`registry.color_sequence_keypoint`. `just wire` rejects a datatype that defines
only one of the two required procedures. Userdata tags are assigned
automatically from the datatype registry's reserved tag range; datatype
bindings should not hardcode a tag.

## Globals

Put global registrations in a separate file under `src/engine/global`:

```odin
Register_My_Globals :: proc(registry: ^Registry) {
	Register_String(registry, "MY_GLOBAL", "value")
}
```

Both `Register_*_Global` and `Register_*_Globals` hooks are discovered.

## Enums

Enums declared in `src/engine/enum/enum.odin` are reflected into Luau by the
same command. Generated regions and `LuaEnumGenerated.odin` should not be
edited by hand.

Ordinary Odin files in a package are compiled automatically. Subsystems without
a registry do not need an additional wiring rule.
