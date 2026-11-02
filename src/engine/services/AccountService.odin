#+build !js
package services

// wire:service global="accountService"

import "core:encoding/json"
import "core:fmt"
import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

AccountService :: struct {
	using service: Service,
}

AccountService_Class := classes.Class_Info {
	name   = "AccountService",
	parent = &Service_Class,
}

account_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(AccountService)
	service.service = Service_Init(&AccountService_Class, "AccountService", data_model)
	return &service.object
}

account_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetMe",
	     "UpdateMe",
	     "ListMyGames",
	     "CreateGame",
	     "ListTokens",
	     "CreateToken",
	     "RevokeToken",
	     "GetAccount",
	     "GetAccountMarketplace",
	     "GetAccountGames",
	     "UploadBanner",
	     "DeleteBanner",
	     "UploadAvatar",
	     "GetService":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

account_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^AccountService)object
	switch method {
	case "GetMe":
		return kinemium_domain_call(
				L,
				&service.service,
				2,
				"GET",
				"/me",
				kinemium_options_empty(),
			),
			true

	case "UpdateMe":
		return kinemium_domain_call(
				L,
				&service.service,
				2,
				"PATCH",
				"/me",
				kinemium_options_json(L, 3),
			),
			true

	case "ListMyGames":
		return kinemium_domain_call(
				L,
				&service.service,
				2,
				"GET",
				"/me/games",
				kinemium_options_empty(),
			),
			true

	case "CreateGame":
		{
			body := make(json.Object, 1)
			defer delete(body)
			body["name"] = json.String(vm.ArgString(L, 3))
			options := kinemium_options_empty()
			options.json = kinemium_marshal(body)
			return kinemium_domain_call(L, &service.service, 2, "POST", "/me/games", options), true
		}

	case "ListTokens":
		{
			options := kinemium_options_empty()
			if vm.IsBoolean(L, 3) {
				options.query = fmt.aprintf(
					"?includeRevoked=%s",
					vm.ArgBoolean(L, 3) ? "true" : "false",
				)
			}
			return kinemium_domain_call(L, &service.service, 2, "GET", "/me/tokens", options), true
		}

	case "CreateToken":
		return kinemium_domain_call(
				L,
				&service.service,
				2,
				"POST",
				"/me/tokens",
				kinemium_options_json(L, 3),
			),
			true

	case "RevokeToken":
		{
			path := strings.concatenate(
				{"/me/tokens/", kinemium_url_encode(vm.ArgString(L, 3))},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"DELETE",
					path,
					kinemium_options_empty(),
				),
				true
		}

	case "GetAccount":
		{
			path := strings.concatenate(
				{"/accounts/", kinemium_url_encode(vm.ArgString(L, 3))},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"GET",
					path,
					kinemium_options_empty(),
				),
				true
		}

	case "GetAccountMarketplace":
		{
			path := strings.concatenate(
				{"/accounts/", kinemium_url_encode(vm.ArgString(L, 3)), "/marketplace"},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"GET",
					path,
					kinemium_options_query(L, 4),
				),
				true
		}

	case "GetAccountGames":
		{
			path := strings.concatenate(
				{"/accounts/", kinemium_url_encode(vm.ArgString(L, 3)), "/games"},
				context.temp_allocator,
			)
			return kinemium_domain_call(
					L,
					&service.service,
					2,
					"GET",
					path,
					kinemium_options_empty(),
				),
				true
		}

	case "UploadBanner":
		return kinemium_upload_image_call(L, &service.service, 2, 3, "POST", "/me/banner"), true

	case "DeleteBanner":
		return kinemium_domain_call(
				L,
				&service.service,
				2,
				"DELETE",
				"/me/banner",
				kinemium_options_empty(),
			),
			true

	case "UploadAvatar":
		return kinemium_upload_image_call(L, &service.service, 2, 3, "POST", "/me/avatar"), true

	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}

account_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^AccountService)object)
}

Register_AccountService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&AccountService_Class,
		account_service_construct,
		account_service_destroy,
		creatable = false,
		get = account_service_get,
		namecall = account_service_namecall,
	)
}
