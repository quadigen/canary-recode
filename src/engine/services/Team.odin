package services

// wire:service global="team"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

Team_Class := classes.Class_Info{
	name   = "Team",
	parent = &classes.Instance_Class,
}

Team :: struct {
	using object: classes.Object,

	team_color:     datatypes.Color3,
	auto_assign:    bool,
	neutral:        bool,
	allow_team_change_on_touch: bool,
	team_order:     i32,
}

Teams_Class := classes.Class_Info{
	name   = "Teams",
	parent = &Service_Class,
}

Teams :: struct {
	using service: Service,
}

teams_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Teams)
	service.service = Service_Init(
		&Teams_Class,
		"Teams",
		data_model,
	)
	return &service.object
}

teams_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetTeams", "GetTeamFromName", "FindChildByName":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

teams_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^Teams)object
	switch method {
	case "GetTeams":
		vm.NewTable(L, len(object.children), 0)
		index := 0
		for child in object.children {
			if !classes.Is_A(child, "Team") {
				continue
			}
			classes.Push_Object(L, child)
			index += 1
			vm.SetArrayValue(L, -2, index)
		}
		return 1, true
	case "GetTeamFromName":
		name := vm.ArgString(L, 2)
		classes.Push_Object(L, classes.Find_First_Child(object, name))
		return 1, true
	case "FindChildByName":
		name := vm.ArgString(L, 2)
		classes.Push_Object(L, classes.Find_First_Child(object, name))
		return 1, true
	}
	return 0, false
}

teams_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^Teams)object)
}

team_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	team := new(Team)
	team.object = classes.Object_Init(&Team_Class, "Team")
	team.auto_assign = true
	return &team.object
}

team_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Team)object)
}

team_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	team := cast(^Team)object
	switch key {
	case "TeamColor":
		datatypes.Push_Color3(L, datatype_registry, team.team_color)
		return true
	case "AutoAssignable":
		vm.PushBoolean(L, team.auto_assign)
		return true
	case "Neutral":
		vm.PushBoolean(L, team.neutral)
		return true
	case "AllowTeamChangeOnTouch":
		vm.PushBoolean(L, team.allow_team_change_on_touch)
		return true
	case "TeamOrder":
		vm.PushNumber(L, f64(team.team_order))
		return true
	}
	return false
}

team_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	team := cast(^Team)object
	switch key {
	case "TeamColor":
		if datatype_registry == nil {
			return false
		}
		team.team_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
		return true
	case "AutoAssignable":
		team.auto_assign = vm.ArgBoolean(L, value_index)
		return true
	case "Neutral":
		team.neutral = vm.ArgBoolean(L, value_index)
		return true
	case "AllowTeamChangeOnTouch":
		team.allow_team_change_on_touch = vm.ArgBoolean(L, value_index)
		return true
	case "TeamOrder":
		team.team_order = i32(vm.ArgNumber(L, value_index))
		return true
	}
	return false
}

Register_Teams_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Teams_Class,
		teams_service_construct,
		teams_service_destroy,
		creatable = false,
		get       = teams_service_get,
		namecall  = teams_service_namecall,
	)
}

Register_Team_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Team_Class,
		team_construct,
		team_destroy,
		get = team_get,
		set = team_set,
		properties = []string{
			"TeamColor",
			"AutoAssignable",
			"Neutral",
			"AllowTeamChangeOnTouch",
			"TeamOrder",
		},
	)
}