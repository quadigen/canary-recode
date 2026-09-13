package datatypes

import vm "../vm"

SecurityCapabilities :: struct {
	bits_low:  u64,
	bits_high: u64,
}

SECURITY_CAPABILITY_PUBLIC_MAX_VALUE :: 73
SECURITY_CAPABILITY_MAX_VALUE        :: 127

SECURITY_CAPABILITY_INTERNAL_SHARED_ACCESS        :: i64(121)
SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS        :: i64(122)
SECURITY_CAPABILITY_INTERNAL_SCRIPT_SOURCE_READ   :: i64(123)
SECURITY_CAPABILITY_INTERNAL_SCRIPT_SOURCE_WRITE  :: i64(124)
SECURITY_CAPABILITY_INTERNAL_SCRIPT_CONTEXT       :: i64(125)
SECURITY_CAPABILITY_INTERNAL_SECURITY_ADMIN       :: i64(126)
SECURITY_CAPABILITY_INTERNAL_SIGNAL_FIRE          :: i64(127)

SECURITY_CAPABILITIES_ALL :: SecurityCapabilities{~u64(0), ~u64(0)}

SecurityCapabilities_Contains_Value :: proc(capabilities: SecurityCapabilities, value: i64) -> bool {
	if value < 0 || value > SECURITY_CAPABILITY_MAX_VALUE { return false }
	if value < 64 { return capabilities.bits_low & (u64(1) << u64(value)) != 0 }
	return capabilities.bits_high & (u64(1) << u64(value-64)) != 0
}

SecurityCapabilities_Add_Value :: proc(capabilities: SecurityCapabilities, value: i64) -> SecurityCapabilities {
	result := capabilities
	if value >= 0 && value <= SECURITY_CAPABILITY_MAX_VALUE {
		if value < 64 {
			result.bits_low |= u64(1) << u64(value)
		} else {
			result.bits_high |= u64(1) << u64(value-64)
		}
	}
	return result
}

SecurityCapabilities_Remove_Value :: proc(capabilities: SecurityCapabilities, value: i64) -> SecurityCapabilities {
	result := capabilities
	if value >= 0 && value <= SECURITY_CAPABILITY_MAX_VALUE {
		if value < 64 {
			result.bits_low &~= u64(1) << u64(value)
		} else {
			result.bits_high &~= u64(1) << u64(value-64)
		}
	}
	return result
}

SecurityCapabilities_Contains :: proc(capabilities, required: SecurityCapabilities) -> bool {
	return capabilities.bits_low & required.bits_low == required.bits_low &&
	       capabilities.bits_high & required.bits_high == required.bits_high
}

SecurityCapabilities_Add :: proc(capabilities, additions: SecurityCapabilities) -> SecurityCapabilities {
	return SecurityCapabilities{
		bits_low  = capabilities.bits_low | additions.bits_low,
		bits_high = capabilities.bits_high | additions.bits_high,
	}
}

SecurityCapabilities_Remove :: proc(capabilities, removals: SecurityCapabilities) -> SecurityCapabilities {
	return SecurityCapabilities{
		bits_low  = capabilities.bits_low &~ removals.bits_low,
		bits_high = capabilities.bits_high &~ removals.bits_high,
	}
}

SecurityCapabilities_From_VM :: proc(capabilities: vm.Thread_Security_Capabilities) -> SecurityCapabilities {
	return SecurityCapabilities{
		bits_low  = capabilities.bits_low,
		bits_high = capabilities.bits_high,
	}
}

SecurityCapabilities_To_VM :: proc(capabilities: SecurityCapabilities) -> vm.Thread_Security_Capabilities {
	return vm.Thread_Security_Capabilities{
		bits_low  = capabilities.bits_low,
		bits_high = capabilities.bits_high,
	}
}
