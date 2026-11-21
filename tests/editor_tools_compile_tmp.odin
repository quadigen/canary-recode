package main
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
main :: proc() {
	v := vm.New()
	defer vm.Close(&v)
	for path in os.args[1:] {
		data, err := os.read_entire_file(path, context.allocator)
		assert(err == nil)
		defer delete(data)
		ok, message := vm.LoadSource(&v, v.L, string(data), path)
		if !ok {fmt.eprintln(path, message); panic("Luau syntax check failed")}
		vm.Pop(v.L, 1)
		fmt.println("PASS", path)
	}
}
