package services

// wire:service global="marketplaceService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

MarketplaceService_Class := classes.Class_Info{
	name   = "MarketplaceService",
	parent = &Service_Class,
}

MarketplaceService :: struct {
	using service: Service,
	product_info_name: string,
	asset_info_name:   string,
}

marketplace_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(MarketplaceService)
	service.service = Service_Init(
		&MarketplaceService_Class,
		"MarketplaceService",
		data_model,
	)
	return &service.object
}

marketplace_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^MarketplaceService)object
	switch key {
	case "ProductInfoName":
		vm.PushString(L, service.product_info_name)
		return true
	case "AssetInfoName":
		vm.PushString(L, service.asset_info_name)
		return true
	case "GetProductInfo",
	     "GetAssetInfo",
	     "PromptProductPurchase",
	     "PromptGamePassPurchase",
	     "PromptSubscriptionPurchase":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

marketplace_service_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^MarketplaceService)object
	switch key {
	case "ProductInfoName":
		service.product_info_name = strings.clone(vm.ArgString(L, value_index))
		return true
	case "AssetInfoName":
		service.asset_info_name = strings.clone(vm.ArgString(L, value_index))
		return true
	}
	return false
}

marketplace_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	switch method {
	case "GetProductInfo":
		vm.NewTable(L, 0, 4)
		vm.PushString(L, "")
		vm.SetField(L, -2, "Name")
		vm.PushString(L, "")
		vm.SetField(L, -2, "Description")
		vm.PushNumber(L, 0)
		vm.SetField(L, -2, "PriceInRobux")
		vm.PushBoolean(L, false)
		vm.SetField(L, -2, "IsForSale")
		return 1, true
	case "GetAssetInfo":
		vm.NewTable(L, 0, 5)
		vm.PushString(L, "")
		vm.SetField(L, -2, "Name")
		vm.PushString(L, "")
		vm.SetField(L, -2, "Description")
		vm.PushString(L, "")
		vm.SetField(L, -2, "AssetType")
		vm.PushNumber(L, 0)
		vm.SetField(L, -2, "Price")
		vm.PushBoolean(L, false)
		vm.SetField(L, -2, "IsForSale")
		return 1, true
	case "PromptProductPurchase",
	     "PromptGamePassPurchase",
	     "PromptSubscriptionPurchase":
		return 0, true
	}
	return 0, false
}

marketplace_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^MarketplaceService)object
	delete(service.product_info_name)
	delete(service.asset_info_name)
	classes.Object_Destroy(object)
	free(service)
}

Register_MarketplaceService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&MarketplaceService_Class,
		marketplace_service_construct,
		marketplace_service_destroy,
		creatable = false,
		get       = marketplace_service_get,
		set       = marketplace_service_set,
		namecall  = marketplace_service_namecall,
	)
}