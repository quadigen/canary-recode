package datatypes

PhysicalProperties :: struct {
	Density:          f32,
	Friction:         f32,
	Elasticity:       f32,
	FrictionWeight:   f32,
	ElasticityWeight: f32,
}

PhysicalProperties_Default :: PhysicalProperties{
	Density          = 0.7,
	Friction         = 0.3,
	Elasticity       = 0.5,
	FrictionWeight   = 100,
	ElasticityWeight = 100,
}

PhysicalProperties_New :: proc(
	density,
	friction,
	elasticity,
	friction_weight,
	elasticity_weight: f32,
) -> PhysicalProperties {
	return PhysicalProperties{
		Density          = density,
		Friction         = friction,
		Elasticity       = elasticity,
		FrictionWeight   = friction_weight,
		ElasticityWeight = elasticity_weight,
	}
}

PhysicalProperties_IsValid :: proc(value: PhysicalProperties) -> bool {
	return value.Density > 0 &&
	       value.Friction >= 0 &&
	       value.Elasticity >= 0 &&
	       value.Elasticity <= 1 &&
	       value.FrictionWeight >= 0 &&
	       value.ElasticityWeight >= 0
}
