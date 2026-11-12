package services

// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"
import "core:strings"

TextChatService_Class := classes.Class_Info {
	name   = "TextChatService",
	parent = &Service_Class,
}

Chat_Message_Status :: enum i32 {
	Unknown                       = 1,
	Success                       = 2,
	Sending                       = 3,
	TextFilterFailed              = 4,
	Floodchecked                  = 5,
	InvalidPrivacySettings        = 6,
	InvalidTextChannelPermissions = 7,
	MessageTooLong                = 8,
	ModerationTimeout             = 9,
}

Chat_Message :: struct {
	id:             u64,
	text:           string,
	metadata:       string,
	prefix_text:    string,
	channel_name:   string,
	sender_user_id: i64,
	status:         Chat_Message_Status,
}

Chat_Channel :: struct {
	name:             string,
	sources:          map[i64]bool,
	direct_requester: i64,
	is_whisper:       bool,
}

Chat_Hooks :: struct {
	ctx:               rawptr,
	can_user_chat:     proc(ctx: rawptr, user_id: i64) -> bool,
	can_users_chat:    proc(ctx: rawptr, sender: i64, recipient: i64) -> bool,
	can_direct_chat:   proc(ctx: rawptr, requester: i64, recipient: i64) -> bool,
	filter_for_user:   proc(
		ctx: rawptr,
		sender: i64,
		recipient: i64,
		text: string,
	) -> (
		string,
		bool,
	),
	should_deliver:    proc(
		ctx: rawptr,
		channel_name: string,
		sender: i64,
		recipient: i64,
	) -> bool,
	deliver_to_client: proc(ctx: rawptr, recipient: i64, message: Chat_Message),
	sending_message:   proc(ctx: rawptr, message: Chat_Message),
	message_received:  proc(ctx: rawptr, message: Chat_Message),
	channel_received:  proc(ctx: rawptr, channel_name: string, message: Chat_Message),
	display_bubble:    proc(ctx: rawptr, adornee: ^classes.Object, text: string),
	get_chat_groups:   proc(ctx: rawptr, user_ids: []i64) -> ([][]string, bool),
}

TextChatService :: struct {
	using service:                Service,
	channels:                     map[string]^Chat_Channel,
	hooks:                        Chat_Hooks,
	next_message_id:              u64,
	max_message_bytes:            int,
	create_default_commands:      bool,
	create_default_text_channels: bool,
	chat_translation_enabled:     bool,
}

text_chat_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(TextChatService)
	service.service = Service_Init(&TextChatService_Class, "TextChatService", data_model)
	service.channels = make(map[string]^Chat_Channel)
	service.create_default_commands = true
	service.create_default_text_channels = true
	service.chat_translation_enabled = false
	service.max_message_bytes = 200
	service.next_message_id = 1

	// These are native channel records. The corresponding TextChannel
	// instances must be created by the engine's Instance lifecycle bridge.
	_ = TextChatService_Create_Channel(service, "RBXGeneral")
	_ = TextChatService_Create_Channel(service, "RBXSystem")
	return &service.object
}

text_chat_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^TextChatService)object
	for _, channel in service.channels {
		delete(channel.sources)
		delete(channel.name)
		free(channel)
	}
	delete(service.channels)
	classes.Object_Destroy(object)
	free(service)
}

TextChatService_Set_Hooks :: proc(service: ^TextChatService, hooks: Chat_Hooks) {
	service.hooks = hooks
}

TextChatService_Create_Channel :: proc(service: ^TextChatService, name: string) -> ^Chat_Channel {
	if len(name) == 0 {return nil}
	if existing, found := service.channels[name]; found {return existing}

	channel := new(Chat_Channel)
	channel.name = strings.clone(name)
	channel.sources = make(map[i64]bool)
	service.channels[channel.name] = channel
	return channel
}

TextChatService_Find_Channel :: proc(service: ^TextChatService, name: string) -> ^Chat_Channel {
	channel, found := service.channels[name]
	if !found {return nil}
	return channel
}

TextChatService_Remove_Channel :: proc(service: ^TextChatService, name: string) -> bool {
	channel := TextChatService_Find_Channel(service, name)
	if channel == nil {return false}
	delete_key(&service.channels, name)
	delete(channel.sources)
	delete(channel.name)
	free(channel)
	return true
}

TextChatService_Can_User_Chat :: proc(service: ^TextChatService, user_id: i64) -> (bool, bool) {
	if user_id <= 0 || service.hooks.can_user_chat == nil {return false, false}
	return service.hooks.can_user_chat(service.hooks.ctx, user_id), true
}

TextChatService_Can_Users_Chat :: proc(
	service: ^TextChatService,
	sender: i64,
	recipient: i64,
) -> (
	bool,
	bool,
) {
	if sender <= 0 || recipient <= 0 || service.hooks.can_users_chat == nil {return false, false}
	return service.hooks.can_users_chat(service.hooks.ctx, sender, recipient), true
}

TextChatService_Can_Users_Direct_Chat :: proc(
	service: ^TextChatService,
	requester: i64,
	recipients: []i64,
) -> (
	[dynamic]i64,
	bool,
) {
	allowed: [dynamic]i64
	if requester <= 0 || service.hooks.can_direct_chat == nil {return allowed, false}
	for recipient in recipients {
		if recipient > 0 &&
		   recipient != requester &&
		   service.hooks.can_direct_chat(service.hooks.ctx, requester, recipient) {
			append(&allowed, recipient)
		}
	}
	return allowed, true
}

TextChatService_Get_Chat_Groups :: proc(
	service: ^TextChatService,
	user_ids: []i64,
) -> (
	[][]string,
	bool,
) {
	if service.hooks.get_chat_groups == nil {return nil, false}
	return service.hooks.get_chat_groups(service.hooks.ctx, user_ids)
}

TextChatService_Add_User :: proc(
	service: ^TextChatService,
	channel: ^Chat_Channel,
	user_id: i64,
	can_send := true,
) -> bool {
	if channel == nil || user_id <= 0 || service.hooks.can_user_chat == nil {return false}
	if !service.hooks.can_user_chat(service.hooks.ctx, user_id) {return false}
	if channel.direct_requester > 0 {
		if service.hooks.can_direct_chat == nil {return false}
		if !service.hooks.can_direct_chat(service.hooks.ctx, channel.direct_requester, user_id) &&
		   channel.direct_requester != user_id {return false}
	}
	channel.sources[user_id] = can_send
	return true
}

TextChatService_Remove_User :: proc(service: ^TextChatService, user_id: i64) {
	// Collect channel names first to avoid altering a map during iteration.
	channels_to_remove: [dynamic]string
	defer delete(channels_to_remove)
	for _, channel in service.channels {
		delete_key(&channel.sources, user_id)
		if channel.is_whisper && (len(channel.sources) < 2) {
			append(&channels_to_remove, channel.name)
		}
	}
	for name in channels_to_remove {
		_ = TextChatService_Remove_Channel(service, name)
	}
}

TextChatService_Create_Whisper :: proc(
	service: ^TextChatService,
	user_a: i64,
	user_b: i64,
) -> ^Chat_Channel {
	if user_a <= 0 || user_b <= 0 || user_a == user_b {return nil}
	if service.hooks.can_direct_chat == nil || service.hooks.can_user_chat == nil {return nil}
	if !service.hooks.can_user_chat(service.hooks.ctx, user_a) ||
	   !service.hooks.can_user_chat(service.hooks.ctx, user_b) ||
	   !service.hooks.can_direct_chat(service.hooks.ctx, user_a, user_b) {
		return nil
	}
	first, second := user_a, user_b
	if first > second {first, second = second, first}
	name := fmt.tprintf("RBXWhisper:%d_%d", first, second)
	if existing := TextChatService_Find_Channel(service, name); existing != nil {
		if existing.is_whisper {return existing}
		return nil
	}
	channel := TextChatService_Create_Channel(service, name)
	if channel == nil {return nil}
	channel.direct_requester = user_a
	channel.is_whisper = true
	channel.sources[user_a] = true
	channel.sources[user_b] = true
	return channel
}

// SERVER SIDE: validates sender and channel membership, checks recipient
// permissions, and filters independently for every recipient. It never routes
// raw unfiltered text through deliver_to_client.
TextChatService_Send :: proc(
	service: ^TextChatService,
	channel: ^Chat_Channel,
	sender: i64,
	text: string,
	metadata := "",
) -> Chat_Message_Status {
	if channel == nil || sender <= 0 {return .InvalidTextChannelPermissions}
	can_send, is_member := channel.sources[sender]
	if !is_member || !can_send {return .InvalidTextChannelPermissions}
	if len(text) == 0 || len(text) > service.max_message_bytes {return .MessageTooLong}
	if len(metadata) > 200 {return .MessageTooLong}

	hooks := &service.hooks
	if hooks.can_user_chat == nil ||
	   hooks.can_users_chat == nil ||
	   hooks.filter_for_user == nil ||
	   hooks.deliver_to_client == nil {
		return .InvalidPrivacySettings
	}
	if !hooks.can_user_chat(hooks.ctx, sender) {return .InvalidPrivacySettings}

	message_id := service.next_message_id
	service.next_message_id += 1
	delivered := false

	for recipient, _ in channel.sources {
		if recipient != sender && !hooks.can_users_chat(hooks.ctx, sender, recipient) {
			continue
		}
		if channel.direct_requester > 0 && recipient != channel.direct_requester {
			if hooks.can_direct_chat == nil ||
			   !hooks.can_direct_chat(hooks.ctx, channel.direct_requester, recipient) {
				continue
			}
		}
		if hooks.should_deliver != nil &&
		   !hooks.should_deliver(hooks.ctx, channel.name, sender, recipient) {
			continue
		}

		filtered, ok := hooks.filter_for_user(hooks.ctx, sender, recipient, text)
		if !ok {continue}
		message := Chat_Message {
			id             = message_id,
			text           = filtered,
			metadata       = metadata,
			channel_name   = channel.name,
			sender_user_id = sender,
			status         = .Success,
		}
		hooks.deliver_to_client(hooks.ctx, recipient, message)
		delivered = true
	}
	if !delivered {return .TextFilterFailed}
	return .Success
}

// CLIENT SIDE: invoke this only after receipt of a server-approved, filtered
// message. Host callbacks should dispatch RBXScriptSignals and UI updates.
TextChatService_Receive :: proc(service: ^TextChatService, message: Chat_Message) {
	if message.status != .Success {return}
	if service.hooks.message_received != nil {
		service.hooks.message_received(service.hooks.ctx, message)
	}
	if service.hooks.channel_received != nil {
		service.hooks.channel_received(service.hooks.ctx, message.channel_name, message)
	}
}

// CLIENT SIDE: call immediately after locally invoking TextChannel:SendAsync.
TextChatService_Sending :: proc(service: ^TextChatService, message: Chat_Message) {
	if service.hooks.sending_message != nil {
		service.hooks.sending_message(service.hooks.ctx, message)
	}
}

// CLIENT SIDE: Roblox-style local-only system messages must not be sent over
// the network and must not be mistaken for filtered messages from a player.
TextChatService_Display_System_Message :: proc(
	service: ^TextChatService,
	channel_name: string,
	text: string,
	metadata := "",
) {
	TextChatService_Receive(
		service,
		Chat_Message {
			id = service.next_message_id,
			text = text,
			metadata = metadata,
			channel_name = channel_name,
			status = .Success,
		},
	)
	service.next_message_id += 1
}

TextChatService_Display_Bubble :: proc(
	service: ^TextChatService,
	adornee: ^classes.Object,
	text: string,
) -> bool {
	if adornee == nil || service.hooks.display_bubble == nil {return false}
	service.hooks.display_bubble(service.hooks.ctx, adornee, text)
	return true
}

// Luau registration. Simple permission methods are connected here. Table-
// returning APIs, Instance-typed arguments, properties, callbacks and
// RBXScriptSignals need the corresponding VM helpers from your codebase.
text_chat_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^TextChatService)object
	switch key {
	case "CreateDefaultCommands":
		vm.PushBoolean(L, service.create_default_commands)
		return true
	case "CreateDefaultTextChannels":
		vm.PushBoolean(L, service.create_default_text_channels)
		return true
	case "ChatTranslationEnabled":
		vm.PushBoolean(L, service.chat_translation_enabled)
		return true
	case "CanUserChatAsync",
	     "CanUsersChatAsync",
	     "CanUsersDirectChatAsync",
	     "DisplayBubble",
	     "GetChatGroupsAsync":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

text_chat_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^TextChatService)object
	switch method {
	case "CanUserChatAsync":
		user_id := i64(vm.ArgNumber(L, 2))
		allowed, configured := TextChatService_Can_User_Chat(service, user_id)
		if !configured {return vm.RaiseError(L, "chat permission provider is not configured"), true}
		vm.PushBoolean(L, allowed)
		return 1, true
	case "CanUsersChatAsync":
		sender := i64(vm.ArgNumber(L, 2))
		recipient := i64(vm.ArgNumber(L, 3))
		allowed, configured := TextChatService_Can_Users_Chat(service, sender, recipient)
		if !configured {return vm.RaiseError(L, "chat permission provider is not configured"), true}
		vm.PushBoolean(L, allowed)
		return 1, true
	case "CanUsersDirectChatAsync":
		return vm.RaiseError(
				L,
				"CanUsersDirectChatAsync requires a VM array reader/writer adapter",
			),
			true
	case "DisplayBubble":
		return vm.RaiseError(
				L,
				"DisplayBubble requires a VM Instance argument adapter and a bubble renderer",
			),
			true
	case "GetChatGroupsAsync":
		return vm.RaiseError(L, "GetChatGroupsAsync requires a VM array reader/writer adapter"),
			true
	}
	return 0, false
}

Register_TextChatService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&TextChatService_Class,
		text_chat_service_construct,
		text_chat_service_destroy,
		creatable = false,
		get = text_chat_service_get,
		namecall = text_chat_service_namecall,
		methods = []string {
			"CanUserChatAsync",
			"CanUsersChatAsync",
			"CanUsersDirectChatAsync",
			"DisplayBubble",
			"GetChatGroupsAsync",
		},
	)
}
