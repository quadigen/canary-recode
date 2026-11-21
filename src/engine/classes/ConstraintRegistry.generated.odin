package classes


Constraint_Steps := [?]Constraint_Step_Entry {
	{&AlignOrientation_Class, AlignOrientation_step},
	{&BallSocketConstraint_Class, BallSocketConstraint_step},
	{&CylindricalConstraint_Class, CylindricalConstraint_step},
	{&HingeConstraint_Class, HingeConstraint_step},
	{&LinearVelocity_Class, LinearVelocity_step},
	{&PlaneConstraint_Class, PlaneConstraint_step},
	{&PrismaticConstraint_Class, PrismaticConstraint_step},
	{&RodConstraint_Class, RodConstraint_step},
	{&RopeConstraint_Class, RopeConstraint_step},
	{&SpringConstraint_Class, SpringConstraint_step},
	{&UniversalConstraint_Class, UniversalConstraint_step},
	{&VectorForce_Class, VectorForce_step},
	{&WeldConstraint_Class, WeldConstraint_step},
}
