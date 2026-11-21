# Kinemium Native Extensions (KNE)

Kinemium Native Extensions (KNE) is a cross-platform SDK that allows developers to extend Kinemium using native programming languages such as C, C++, Odin, Rust, and Zig.

KNE provides a C-compatible API and language bindings that expose Kinemium's internal systems, including services, classes, packages, the Luau virtual machine, rendering, physics, and more.

Developers can use KNE to create custom engine functionality, integrate external libraries, introduce new systems, and extend existing features without modifying Kinemium's source code.

KNE is designed to provide a consistent, versioned interface across supported platforms and programming languages, making native extensions portable and maintainable.
## Plugin author API

Start with `#include "kne_plugin.h"` in C/C++, or import
`include/sdk/bindings/odin` in Odin. The original `kne.h` and `KNE_*`
types remain available for binary-compatible low-level use. No ABI bump is
needed for these helpers.

In Odin, create the plugin context using the host supplied to
`kne_extension_entry` and the extension handle supplied to each callback:

```odin
on_load :: proc "c" (ext: kne.Extension_Handle) -> i32 {
    p := kne.plugin(host, ext)
    workspace := kne.get_service(p, "Workspace")
    folder := kne.new_instance(p, "Folder")
    if workspace == nil || folder == nil {return 0}
    kne.set_name(p, folder, "MyPlugin")
    kne.set_parent(p, folder, workspace)
    return 1
}
```

In C and C++ the same operations are prefixed with `kne_`:

```c
kne_plugin plugin = kne_make_plugin(host, ext);
kne_instance folder = kne_new_instance(plugin, "Folder");
if (folder) {
    kne_set_name(plugin, folder, "MyPlugin");
    kne_set_parent(plugin, folder, kne_get_service(plugin, "Workspace"));
}
```

| Task | Author-facing helper (Odin; add `kne_` in C) |
| --- | --- |
| Find services and instances | `get_service`, `new_instance`, `find_child`, `destroy_instance` |
| Read/write properties | `get_property`, `set_property`, `value_string`, `value_number` |
| Call a method | `call_method` |
| Register plugin features | `register_class`, `register_library_function`, `register_datatype` |
| Luau arguments and results | `get_argument`, `push_result`, `run_luau` |
| Events | `get_signal`, `connect`, `connect_once`, `disconnect` |
| Errors | `last_error`, `raise_error`, `log` |

Odin accepts native strings and slices and returns a value and success flag
for property access. A successful read may return Nil, including for a
missing member when the engine returns nil. Method calls and Luau execution
return a result count or a negative error status; an empty output slice
discards results. Arguments and results are borrowed for the current callback.
Luau stack indices start at 1, and child/service enumeration indices start at 0.
The plugin context is not a global singleton and must only be used during
valid engine callbacks on the owning VM thread.

## ABI 3.1

The host retains the 3.0 API prefix and appends three VM functions. Check
`host->abi_minor >= 1` and the module size before using the new fields.

- `vm->execute(ext, source, args, count, out, capacity)` runs synchronous
  Luau with native arguments available through `...`. It returns the number
  of results written or a negative status on compilation/runtime error
  (`core->last_error`). This provides access to engine-exposed services,
  instances, globals, libraries and datatypes without per-method SDK additions.
- `vm->get_buffer` borrows mutable bytes from a Luau buffer on the stack;
  `vm->push_buffer` copies native bytes into a new Luau buffer.
- Buffers, threads and otherwise unrecognized Luau values round-trip as borrowed
  stack references. Like tables and functions, these are callback-scoped.
- Instance property access uses normal engine dispatch, including validation,
  property-change notifications and inherited members.

Call the host on its owning VM thread. The execution bridge is synchronous;
yielding APIs require the engine scheduler and are not guaranteed to work
through it. Direct internal renderer/physics hooks not exposed by the engine
API are not automatically exposed by this bridge.
