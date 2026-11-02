package main

import engine_runtime "../src/engine/runtime"
import target "../src/engine/target"
import vm "../src/engine/vm"
import sandbox "../src/sandboxed"
import "core:fmt"
import "core:os"

DATASTORE_SMOKE_PATH :: "./kinemium_datastore_smoke"

main :: proc() {
	_ = os.remove_all(DATASTORE_SMOKE_PATH)
	_ = os.set_env("KINEMIUM_DATASTORE_PATH", DATASTORE_SMOKE_PATH)
	target.set_mode(.Server)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	sandbox.init_runtime(&script_vm, &environment, nil)
	defer {
		vm.Close(&script_vm)
		sandbox.shutdown()
		_ = os.remove_all(DATASTORE_SMOKE_PATH)
	}

	ok, err := vm.Run(
		&script_vm,
		`
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("KinemiumSmoke")
local key = "kinemium-smoke"
store:RemoveAsync(key)
store:SetAsync(key, {count = 1, label = "first"})
local value, info = store:GetAsync(key)
assert(value.count == 1 and value.label == "first")
assert(typeof(info) == "DataStoreKeyInfo")
local updated, updated_info = store:UpdateAsync(key, function(old)
    old.count = old.count + 1
    return old
end)
assert(updated.count == 2 and updated.label == "first")
assert(updated_info.Version ~= info.Version)
local removed = store:RemoveAsync(key)
assert(removed.count == 2)
local missing = store:GetAsync(key)
assert(missing == nil)

DataStoreService:RemoveDataStore("KinemiumDatatypes")
local typed = DataStoreService:GetDataStore("KinemiumDatatypes")
typed:RemoveAsync("types")
local v3 = Vector3.new(1, 2, 3)
local cf = CFrame.new(4, 5, 6)
local c3 = Color3.new(0.1, 0.2, 0.3)
local u = UDim.new(0.5, 10)
local u2 = UDim2.new(0.5, 10, 0.25, 20)
local nr = NumberRange.new(3, 7)
local ns = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(1, 5),
})
local cs = ColorSequence.new(Color3.new(1, 0, 0), Color3.new(0, 0, 1))
local ray = Ray.new(Vector3.new(1, 2, 3), Vector3.new(0, 1, 0))
local region = Region3.new(Vector3.new(0, 0, 0), Vector3.new(2, 4, 6))
local axes = Axes.new(Enum.Axis.X, Enum.Axis.Z)
local faces = Faces.new(Enum.NormalId.Top, Enum.NormalId.Front)
local bc = BrickColor.new("Bright red")
local date = DateTime.fromUnixTimestamp(1234)
local quat = Quaternion.new(0, 0, 0, 1)
local tween = TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 3, true, 0.5)
local props = PhysicalProperties.new(1, 0.5, 0.2, 10, 20)
local waypoint = PathWaypoint.new(Vector3.new(1, 2, 3), Enum.PathWaypointAction.Jump, "label")
local rect = Rect.new(0, 0, 10, 20)
local enum_item = Enum.Material.Plastic
typed:SetAsync("types", {
    v3 = v3,
    cf = cf,
    c3 = c3,
    u = u,
    u2 = u2,
    nr = nr,
    ns = ns,
    cs = cs,
    ray = ray,
    region = region,
    axes = axes,
    faces = faces,
    bc = bc,
    date = date,
    quat = quat,
    tween = tween,
    props = props,
    waypoint = waypoint,
    rect = rect,
    enum_item = enum_item,
    nested = {list = {v3, c3}, deep = {cf = cf}},
})
local got = typed:GetAsync("types")
assert(got.v3.X == 1 and got.v3.Y == 2 and got.v3.Z == 3)
assert(got.cf.X == 4 and got.cf.Y == 5 and got.cf.Z == 6)
assert(math.abs(got.c3.R - 0.1) < 1e-6)
assert(math.abs(got.c3.G - 0.2) < 1e-6)
assert(math.abs(got.c3.B - 0.3) < 1e-6)
assert(got.u.Scale == 0.5 and got.u.Offset == 10)
assert(got.u2.XScale == 0.5 and got.u2.XOffset == 10)
assert(got.u2.YScale == 0.25 and got.u2.YOffset == 20)
assert(got.nr.Min == 3 and got.nr.Max == 7)
assert(#got.ns.Keypoints == 2 and got.ns.Keypoints[2].Value == 5)
assert(#got.cs.Keypoints == 2 and math.abs(got.cs.Keypoints[2].Value.B - 1) < 1e-6)
assert(got.ray.Origin.X == 1 and got.ray.Direction.Y == 1)
assert(got.region.Size.X == 2 and got.region.Size.Y == 4 and got.region.Size.Z == 6)
assert(got.axes.X == true and got.axes.Z == true and got.axes.Y == false)
assert(got.faces.Top == true and got.faces.Front == true and got.faces.Bottom == false)
assert(tostring(got.bc.Number) == "21" and got.bc.Name == "Bright red")
if tonumber(got.date.UnixTimestamp) ~= 1234 then
    error("date " .. tostring(got.date.UnixTimestamp) .. "/" .. tostring(got.date.UnixTimestampMillis))
end
assert(got.quat.W == 1)
assert(got.tween.Time == 2 and got.tween.EasingStyle == Enum.EasingStyle.Linear)
assert(got.props.Density == 1 and got.props.FrictionWeight == 10)
assert(got.waypoint.Position.X == 1 and got.waypoint.Action == Enum.PathWaypointAction.Jump)
assert(got.waypoint.Label == "label")
assert(got.rect.Width == 10 and got.rect.Height == 20)
assert(got.enum_item == Enum.Material.Plastic)
assert(got.nested.list[1].X == 1 and math.abs(got.nested.list[2].B - 0.3) < 1e-6)
assert(got.nested.deep.cf.Z == 6)
DataStoreService:RemoveDataStore("KinemiumDatatypes")

DataStoreService:RemoveDataStore("KinemiumOrdered")
local ordered = DataStoreService:GetOrderedDataStore("KinemiumOrdered")
ordered:SetAsync("a", 10)
ordered:SetAsync("b", 5)
ordered:SetAsync("c", 20)
local ordered_pages = ordered:GetSortedAsync(true, 2)
local ordered_first = ordered_pages:GetCurrentPage()
assert(#ordered_first == 2)
assert(ordered_first[1].key == "b" and ordered_first[2].key == "a")
ordered_pages:AdvanceToNextPageAsync()
local ordered_second = ordered_pages:GetCurrentPage()
assert(#ordered_second == 1 and ordered_second[1].key == "c")
DataStoreService:RemoveDataStore("KinemiumOrdered")

DataStoreService:RemoveDataStore("KinemiumVersions")
local versioned = DataStoreService:GetDataStore("KinemiumVersions")
versioned:SetAsync("v", "one")
versioned:SetAsync("v", "two")
local version_pages = versioned:ListVersionsAsync("v", nil, nil, nil, 10)
local version_entries = version_pages:GetCurrentPage()
assert(#version_entries >= 2)
local found_version = false
for _, entry in version_entries do
    if entry.key == "v" and entry.value == "one" then
        local old, old_info = versioned:GetVersionAsync("v", entry.keyInfo.Version)
        assert(old == "one")
        found_version = true
    end
end
assert(found_version)
DataStoreService:RemoveDataStore("KinemiumVersions")
`,
		"datastore_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("datastore smoke failed")
	}

	engine_runtime.Environment_Set_Mode(&environment, .Singleplayer)
	ok, err = vm.Run(
		&script_vm,
		`
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("KinemiumSingleplayer")
store:SetAsync("local", 1)
assert(store:GetAsync("local") == 1)
DataStoreService:RemoveDataStore("KinemiumSingleplayer")
`,
		"datastore_singleplayer",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("datastore singleplayer failed")
	}

	engine_runtime.Environment_Set_Mode(&environment, .Client)
	ok, err = vm.Run(
		&script_vm,
		`
local DataStoreService = game:GetService("DataStoreService")
assert(type(DataStoreService:GetChildren()) == "table")
local allowed = pcall(function()
    return DataStoreService:GetDataStore("KinemiumClientDenied")
end)
assert(not allowed)
`,
		"datastore_client_denied",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("datastore client denial failed")
	}

	fmt.println("DATASTORE_SMOKE_PASSED")
}
