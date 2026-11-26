#+build js
package services
import datatypes "../datatypes"
import vm "../vm"
World_Cells_Step :: proc(workspace: ^Workspace, L: ^vm.State) {}
World_Cells_Destroy :: proc(workspace: ^Workspace) {}
World_Cells_Namecall :: proc(
	workspace: ^Workspace,
	L: ^vm.State,
	d: ^datatypes.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "ConfigureCellStreaming",
	     "RegisterWorldCell",
	     "SetCellStreamingFocus",
	     "GetCellStreamingStats",
	     "GetWorldCells",
	     "RetryWorldCell",
	     "UnregisterWorldCell":
		return vm.RaiseError(
				L,
				"automatic world cell disk residency is unavailable on this platform",
			),
			true
	}
	return 0, false
}
