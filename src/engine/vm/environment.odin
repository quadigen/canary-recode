package luau

Environment_Installer :: proc(vm: ^VM, ctx: rawptr)

Environment_Module :: struct {
	name:    string,
	ctx:     rawptr,
	install: Environment_Installer,
}

Environment :: struct {
	modules: [dynamic]Environment_Module,
}

Environment_Init :: proc() -> Environment {
	return Environment{}
}

Environment_Add :: proc(
	environment: ^Environment,
	name: string,
	install: Environment_Installer,
	ctx: rawptr = nil,
) {
	assert(environment != nil)
	assert(install != nil)
	append(&environment.modules, Environment_Module{
		name    = name,
		ctx     = ctx,
		install = install,
	})
}

Environment_Install :: proc(environment: ^Environment, vm: ^VM) {
	assert(environment != nil)
	assert_open(vm)

	for module in environment.modules {
		module.install(vm, module.ctx)
	}
}

Environment_Destroy :: proc(environment: ^Environment) {
	if environment == nil {
		return
	}
	delete(environment.modules)
	environment.modules = nil
}

