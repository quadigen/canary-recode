package services

import "core:fmt"
import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import target "../target"
import vm "../vm"

PlayerScripts_Class := classes.Class_Info {
	name   = "PlayerScripts",
	parent = &classes.Instance_Class,
}

PlayerGui_Class := classes.Class_Info {
	name   = "PlayerGui",
	parent = &classes.Instance_Class,
}

StarterCharacterScripts_Class := classes.Class_Info {
	name   = "StarterCharacterScripts",
	parent = &classes.Instance_Class,
}

PlayerScripts :: struct {
	using object: classes.Object,
}

PlayerGui :: struct {
	using object: classes.Object,
}

StarterCharacterScripts :: struct {
	using object: classes.Object,
}

player_scripts_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	container := new(PlayerScripts)
	container.object = classes.Object_Init(&PlayerScripts_Class, "PlayerScripts")
	return &container.object
}

player_gui_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	container := new(PlayerGui)
	container.object = classes.Object_Init(&PlayerGui_Class, "PlayerGui")
	return &container.object
}

starter_character_scripts_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	container := new(StarterCharacterScripts)
	container.object = classes.Object_Init(
		&StarterCharacterScripts_Class,
		"StarterCharacterScripts",
	)
	return &container.object
}

player_scripts_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	container := cast(^PlayerScripts)object
	classes.Object_Destroy(object)
	free(container)
}

player_gui_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	container := cast(^PlayerGui)object
	classes.Object_Destroy(object)
	free(container)
}

starter_character_scripts_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	container := cast(^StarterCharacterScripts)object
	classes.Object_Destroy(object)
	free(container)
}

Register_PlayerScripts_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&PlayerScripts_Class,
		player_scripts_construct,
		player_scripts_destroy,
		creatable = false,
	)
}

Register_PlayerGui_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&PlayerGui_Class,
		player_gui_construct,
		player_gui_destroy,
		creatable = false,
	)
}

Register_StarterCharacterScripts_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&StarterCharacterScripts_Class,
		starter_character_scripts_construct,
		starter_character_scripts_destroy,
		creatable = false,
	)
}

ClientScripts_Is_Template :: proc(object: ^classes.Object) -> bool {
	if object == nil {
		return false
	}
	switch classes.Get_Class_Name(object) {
	case "StarterCharacterScripts":
		return true
	case "PlayerScripts":
		return object.parent != nil && classes.Is_A(object.parent, "StarterPlayer")
	}
	return false
}

ClientScripts_In_Template :: proc(object: ^classes.Object) -> bool {
	current := object
	for current != nil {
		if ClientScripts_Is_Template(current) {
			return true
		}
		current = current.parent
	}
	return false
}

ClientScripts_Is_Client_Container :: proc(object: ^classes.Object) -> bool {
	if object == nil {
		return false
	}
	name := classes.Get_Class_Name(object)
	return name == "PlayerScripts" || name == "PlayerGui"
}

client_scripts_ensure_child :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	parent: ^classes.Object,
	class_name, name: string,
) -> ^classes.Object {
	if registry == nil || L == nil || parent == nil || parent.destroyed {
		return nil
	}

	existing := classes.Find_First_Child(parent, name)
	if existing != nil && !existing.destroyed {
		return existing
	}

	object, ok := classes.Push_New(registry, &vm.VM{L = L}, class_name, false)
	if !ok || object == nil {
		return nil
	}
	classes.Set_Name(object, name)
	classes.Set_Parent(object, parent)
	vm.Pop(L)
	return object
}

client_scripts_copy_contents :: proc(
	L: ^vm.State,
	registry: ^classes.Registry,
	source, destination: ^classes.Object,
) -> int {
	if L == nil || registry == nil || source == nil || destination == nil {
		return 0
	}

	copied := 0
	for child in source.children {
		if child == nil || child.destroyed || !child.archivable {
			continue
		}
		clone, ok := classes.Clone_Object(L, registry, child)
		if !ok || clone == nil {
			continue
		}
		classes.Set_Parent(clone, destination)

		vm.Pop(L)
		copied += 1
	}
	return copied
}

client_scripts_sync_template :: proc(
	L: ^vm.State,
	registry: ^classes.Registry,
	source, destination: ^classes.Object,
) -> int {
	if L == nil || registry == nil || source == nil || destination == nil {
		return 0
	}

	copied := 0
	for child in source.children {
		if child == nil || child.destroyed || !child.archivable {
			continue
		}
		if existing := classes.Find_First_Child(destination, child.name); existing != nil {
			continue
		}
		clone, ok := classes.Clone_Object(L, registry, child)
		if !ok || clone == nil {
			continue
		}
		classes.Set_Parent(clone, destination)
		vm.Pop(L)
		copied += 1
	}
	return copied
}

ClientScripts_Ensure_Player_Containers :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	player: ^Player,
) -> (player_scripts, player_gui: ^classes.Object) {
	if registry == nil || L == nil || player == nil || player.destroyed {
		return nil, nil
	}

	if player.player_scripts == nil || player.player_scripts.destroyed {
		player.player_scripts = client_scripts_ensure_child(
			registry,
			L,
			&player.object,
			"PlayerScripts",
			"PlayerScripts",
		)
	}
	if player.player_gui == nil || player.player_gui.destroyed {
		player.player_gui = client_scripts_ensure_child(
			registry,
			L,
			&player.object,
			"PlayerGui",
			"PlayerGui",
		)
	}

	return player.player_scripts, player.player_gui
}

ClientScripts_Prepare_Local_Player :: proc(
	data_model: ^DataModel,
	player: ^Player,
) -> int {
	if data_model == nil || data_model.registry == nil || player == nil || player.destroyed {
		return 0
	}
	registry := data_model.registry
	L := registry.vm_state.L
	if L == nil {
		return 0
	}

	starter_player := cast(^StarterPlayer)Ensure_Service(registry, "StarterPlayer")
	if starter_player == nil || starter_player.destroyed {
		return 0
	}

	starter_scripts := client_scripts_ensure_child(
		registry.classes,
		L,
		&starter_player.object,
		"PlayerScripts",
		"StarterPlayerScripts",
	)

	starter_character_scripts := client_scripts_ensure_child(
		registry.classes,
		L,
		&starter_player.object,
		"StarterCharacterScripts",
		"StarterCharacterScripts",
	)

	// A server that authored into its own StarterPlayerScripts replicates the
	// whole container to us. Move its contents into our local template, then
	// destroy the replicated shell so its name does not shadow the template
	// and its copies are not mistaken for already-synced scripts.
	for container in starter_player.object.children {
		if container == nil ||
		   container.destroyed ||
		   !ClientScripts_Is_Client_Container(container) ||
		   container == starter_scripts ||
		   container == starter_character_scripts {
			continue
		}
		destination := starter_scripts
		if container.name == "StarterCharacterScripts" ||
		   classes.Is_A(container, "StarterCharacterScripts") {
			destination = starter_character_scripts
		}
		if destination != nil {
			copied := client_scripts_copy_contents(L, registry.classes, container, destination)
			if copied > 0 {fmt.eprintln("[ClientScripts] merged", copied, "template items from", container.name)}
		}
		classes.Destroy_Hierarchy(container)
	}

	player_scripts, _ := ClientScripts_Ensure_Player_Containers(
		registry.classes,
		L,
		player,
	)

	copied := 0
	if player_scripts != nil {
		copied += client_scripts_sync_template(
			L,
			registry.classes,
			starter_scripts,
			player_scripts,
		)
	}

	if player.character != nil && !player.character.destroyed {
		copied += client_scripts_sync_template(
			L,
			registry.classes,
			starter_character_scripts,
			&player.character.object,
		)
	}

	return copied
}

ClientScripts_Run :: proc(
	script_context: ^ScriptContext,
	data_model: ^DataModel,
) -> bool {
	if script_context == nil || data_model == nil || data_model.registry == nil {
		return false
	}
	registry := data_model.registry
	if registry.mode == .Server || registry.vm_state == nil || registry.vm_state.L == nil {
		return false
	}

	players_object := Ensure_Service(registry, "Players")
	players := cast(^Players)players_object
	if players == nil || players.destroyed || players.local_player == nil {
		return false
	}
	player := players.local_player

	ClientScripts_Prepare_Local_Player(data_model, player)

	player_scripts, player_gui := ClientScripts_Ensure_Player_Containers(
		registry.classes,
		registry.vm_state.L,
		player,
	)

	roots: [dynamic]^classes.Object
	defer delete(roots)
	if player_scripts != nil {
		append(&roots, player_scripts)
	}
	if player_gui != nil {
		append(&roots, player_gui)
	}
	if player.character != nil && !player.character.destroyed {
		append(&roots, &player.character.object)
	}

	started := false
	for root in roots {
		descendants: [dynamic]^classes.Object
		classes.append_descendants(&descendants, root)
		for instance in descendants {
			if instance == nil || instance.destroyed {
				continue
			}
			kind, ok := classes.Script_Kind_Of(instance)
			if !ok || kind != .LocalScript {
				continue
			}
			common := classes.Script_Common_Of(instance)
			if common == nil || !common.enabled {
				continue
			}
			if ScriptContext_Run_Script(script_context, instance) {
				started = true
			}
		}
		delete(descendants)
	}

	return started
}

ClientScripts_Mode_Allows_Local_Script :: proc(mode: target.Mode) -> bool {
	return mode == .Client || mode == .Standalone
}

ClientScripts_Describe_Containers :: proc() -> string {
	return strings.concatenate({
		"PlayerScripts (from StarterPlayerScripts), PlayerGui, Character ",
		"(from StarterCharacterScripts)",
	})
}
