constexpr uint32_t kMaxRopeLinks = JPH_ROPE_MAX_POINTS - 1;
constexpr uint64_t kRopeLinkFlag = uint64_t{1} << 62;

struct RopePoints {
	std::array<JPH::RVec3, JPH_ROPE_MAX_POINTS> positions;
	uint32_t count;
};

RopePoints RopeRestPoints(JPH::RVec3Arg start, JPH::RVec3Arg end, float length) {
	const JPH::RVec3 chord = end - start;
	const float span = static_cast<float>(chord.Length());
	const auto links = static_cast<uint32_t>(std::clamp(std::ceil(length / 0.65f), 2.0f, float(kMaxRopeLinks)));
	RopePoints result;
	result.count = links + 1;
	result.positions[0] = start;
	result.positions[links] = end;
	if (length <= span * 1.0001f || length <= 0.001f) {
		for (uint32_t i = 1; i < links; ++i)
			result.positions[i] = start + chord * (double(i) / links);
		return result;
	}

	// A circular arc gives the relaxed rope an initial bend with equal link lengths.
	const auto axis = JPH::Vec3(chord).NormalizedOr(JPH::Vec3::sAxisX());
	const auto gravity = -JPH::Vec3::sAxisY();
	const auto down = (gravity - axis * gravity.Dot(axis)).NormalizedOr(axis.GetNormalizedPerpendicular());
	const float ratio = span / length;
	float low = 0.0f, high = JPH::JPH_PI;
	for (int i = 0; i < 20; ++i) {
		const float angle = (low + high) * 0.5f;
		if (std::sin(angle) > ratio * links * std::sin(angle / links))
			low = angle;
		else
			high = angle;
	}
	const float halfAngle = (low + high) * 0.5f;
	const float radius = length / (2.0f * links * std::sin(halfAngle / links));
	const JPH::RVec3 midpoint = start + chord * 0.5;
	for (uint32_t i = 1; i < links; ++i) {
		const float angle = halfAngle * (2.0f * i / links - 1.0f);
		result.positions[i] = midpoint + JPH::RVec3(
			axis * (radius * std::sin(angle)) + down * (radius * (std::cos(angle) - std::cos(halfAngle))));
	}
	return result;
}

struct Rope;

struct RopeLink {
	const Rope *rope;
	uint32_t index;
	JPH::BodyID id;
};

class RopeSeedFilter final : public JPH::BodyFilter {
public:
	RopeSeedFilter(JPH::BodyID first, JPH::BodyID second) : mFirst(first), mSecond(second) { }
	bool ShouldCollide(const JPH::BodyID &id) const override { return id != mFirst && id != mSecond; }
	bool ShouldCollideLocked(const JPH::Body &body) const override { return body.IsRigidBody() && !body.IsSensor(); }
private:
	JPH::BodyID mFirst, mSecond;
};

struct Rope {
	JPH::PhysicsSystem *physics = nullptr;
	JPH::BodyID anchors[2];
	std::array<RopeLink, kMaxRopeLinks> links;
	std::array<JPH::Ref<JPH::TwoBodyConstraint>, JPH_ROPE_MAX_POINTS> joints;
	uint32_t count = 0;
	uint32_t neighborExclusion = 1;
	float halfSpan = 0.0f;
	bool canCollide = true;
	bool added = false;

	~Rope() {
		if (added && canCollide)
			WakeNearby();
		if (added)
			for (uint32_t i = 0; i <= count; ++i)
				physics->RemoveConstraint(joints[i]);
		auto &bodies = physics->GetBodyInterface();
		for (uint32_t i = 0; i < count; ++i) {
			const auto id = links[i].id;
			if (added)
				bodies.RemoveBody(id);
			bodies.DestroyBody(id);
		}
	}

	void WakeNearby() const {
		JPH::AABox bounds;
		for (uint32_t i = 0; i < count; ++i) {
			JPH::BodyLockRead lock(physics->GetBodyLockInterface(), links[i].id);
			if (lock.Succeeded())
				bounds.Encapsulate(lock.GetBody().GetWorldSpaceBounds());
		}
		if (!bounds.IsValid())
			return;
		bounds.ExpandBy(JPH::Vec3::sReplicate(physics->GetPhysicsSettings().mSpeculativeContactDistance));
		auto &bodies = physics->GetBodyInterface();
		bodies.ActivateBodiesInAABox(bounds, JPH::BroadPhaseLayerFilter(), JPH::ObjectLayerFilter());
	}

	void KeepSeedAboveObstacles(RopePoints &points, float radius, JPH::ObjectLayer layer) const {
		const auto start = points.positions[0];
		const auto axis = JPH::Vec3(points.positions[points.count - 1] - start).NormalizedOr(JPH::Vec3::sAxisX());
		const auto project = [&](JPH::RVec3Arg point) {
			return start + JPH::RVec3(axis) * (point - start).Dot(JPH::RVec3(axis));
		};
		const JPH::SphereShape sphere(radius);
		const RopeSeedFilter filter(anchors[0], anchors[1]);
		JPH::ShapeCastSettings settings;
		const auto clearance = [&](const RopePoints &path) {
			float fraction = 1.0f;
			for (uint32_t i = 1; i + 1 < path.count && fraction > 0.0f; ++i) {
				const auto from = project(path.positions[i]);
				const auto displacement = JPH::Vec3(path.positions[i] - from);
				if (displacement.LengthSq() < 1e-8f)
					continue;
				const JPH::RShapeCast cast(&sphere, JPH::Vec3::sReplicate(1), JPH::RMat44::sTranslation(from), displacement * fraction);
				JPH::ClosestHitCollisionCollector<JPH::CastShapeCollector> hit;
				physics->GetNarrowPhaseQuery().CastShape(cast, settings, JPH::RVec3::sZero(), hit,
					physics->GetDefaultBroadPhaseLayerFilter(layer), physics->GetDefaultLayerFilter(layer), filter);
				if (hit.HadHit())
					fraction = std::max(0.0f, fraction * hit.mHit.mFraction - 0.04f / displacement.Length());
			}
			return fraction;
		};
		const float fraction = clearance(points);
		if (fraction == 1.0f)
			return;

		// Tilt the initial sag around the anchor axis to keep the link lengths exact.
		for (float sign : {1.0f, -1.0f}) {
			RopePoints tilted = points;
			const float sideways = sign * std::sqrt(1.0f - fraction * fraction);
			for (uint32_t i = 1; i + 1 < points.count; ++i) {
				const auto from = project(points.positions[i]);
				const auto drop = JPH::Vec3(points.positions[i] - from);
				tilted.positions[i] = from + JPH::RVec3(fraction * drop + sideways * axis.Cross(drop));
			}
			if (clearance(tilted) == 1.0f) {
				points = tilted;
				return;
			}
		}
		for (uint32_t i = 1; i + 1 < points.count; ++i) {
			const auto from = project(points.positions[i]);
			points.positions[i] = from + (points.positions[i] - from) * fraction;
		}
	}

	bool Create(RopePoints points, float length, float radius, JPH::ObjectLayer layer) {
		const uint32_t linkCount = points.count - 1;
		if (canCollide)
			KeepSeedAboveObstacles(points, radius, layer);
		halfSpan = length / (2.0f * linkCount);
		neighborExclusion = static_cast<uint32_t>(std::clamp(std::ceil(radius / halfSpan), 1.0f, float(linkCount)));
		JPH::RefConst<JPH::Shape> shape = new JPH::CapsuleShape(halfSpan, radius);
		const auto localSpan = JPH::Vec3(0, halfSpan, 0);
		auto &bodies = physics->GetBodyInterface();
		std::array<JPH::Body *, kMaxRopeLinks> segments;
		for (uint32_t i = 0; i < linkCount; ++i) {
			const auto from = points.positions[i];
			const auto delta = points.positions[i + 1] - from;
			const auto direction = JPH::Vec3(delta).NormalizedOr(JPH::Vec3::sAxisY());
			const auto rotation = JPH::Quat::sFromTo(JPH::Vec3::sAxisY(), direction);
			JPH::BodyCreationSettings settings(shape, from + delta * 0.5, rotation, JPH::EMotionType::Dynamic, layer);
			settings.mUserData = kRopeLinkFlag | reinterpret_cast<uintptr_t>(&links[i]);
			settings.mMotionQuality = JPH::EMotionQuality::LinearCast;
			settings.mFriction = 0.7f;
			settings.mLinearDamping = 0.4f;
			settings.mAngularDamping = 0.7f;
			settings.mOverrideMassProperties = JPH::EOverrideMassProperties::CalculateInertia;
			settings.mMassPropertiesOverride.mMass = std::max(0.012f, 1.4f * JPH::JPH_PI * radius * radius * 2 * halfSpan);
			segments[i] = bodies.CreateBody(settings);
			if (segments[i] == nullptr)
				return false;
			links[i] = {this, i, segments[i]->GetID()};
			++count;
		}

		{
			JPH::BodyLockMultiWrite lock(physics->GetBodyLockInterface(), anchors, 2);
			auto *startBody = lock.GetBody(0);
			auto *endBody = lock.GetBody(1);
			if (startBody == nullptr || endBody == nullptr)
				return false;
			JPH::PointConstraintSettings joint;
			joint.mNumVelocityStepsOverride = 32;
			joint.mNumPositionStepsOverride = 12;
			for (uint32_t i = 0; i <= count; ++i) {
				auto *left = i == 0 ? startBody : segments[i - 1];
				auto *right = i == count ? endBody : segments[i];
				joint.mPoint1 = i == 0 ? points.positions[0] : left->GetPosition() + JPH::RVec3(left->GetRotation() * localSpan);
				joint.mPoint2 = i == count ? points.positions[count] : right->GetPosition() - JPH::RVec3(right->GetRotation() * localSpan);
				joints[i] = joint.Create(*left, *right);
			}
		}
		for (uint32_t i = 0; i <= count; ++i)
			physics->AddConstraint(joints[i]);
		for (uint32_t i = 0; i < count; ++i)
			bodies.AddBody(links[i].id, JPH::EActivation::Activate);
		bodies.ActivateBody(anchors[0]);
		bodies.ActivateBody(anchors[1]);
		added = true;
		return true;
	}

	uint32_t GetPoints(JPH_RVec3 *points) const {
		const auto &bodies = physics->GetBodyInterface();
		JPH::RVec3 previous;
		for (uint32_t i = 0; i < count; ++i) {
			JPH::RVec3 center;
			JPH::Quat rotation;
			bodies.GetPositionAndRotation(links[i].id, center, rotation);
			const JPH::RVec3 offset(rotation * JPH::Vec3(0, halfSpan, 0));
			const auto start = center - offset;
			points[i] = FromJPH(i == 0 ? start : (start + previous) * 0.5);
			previous = center + offset;
		}
		points[count] = FromJPH(previous);
		return count + 1;
	}
};

const RopeLink *GetRopeLink(const JPH::Body &body) {
	const auto data = body.GetUserData();
	if (!body.IsRigidBody() || (data & (kRopeLinkFlag | kMaterialWeightsFlag)) != kRopeLinkFlag)
		return nullptr;
	return reinterpret_cast<const RopeLink *>(static_cast<uintptr_t>(data & ~kRopeLinkFlag));
}

bool RopeCanCollide(const RopeLink *link, JPH::BodyID other) {
	return link == nullptr || (link->rope->canCollide &&
		other != link->rope->anchors[0] && other != link->rope->anchors[1]);
}

class RopeCollisionFilter final : public JPH::SimShapeFilter {
public:
	bool ShouldCollide(
		const JPH::Body &a, const JPH::Shape *, const JPH::SubShapeID &,
		const JPH::Body &b, const JPH::Shape *, const JPH::SubShapeID &) const override {
		const auto *linkA = GetRopeLink(a);
		const auto *linkB = GetRopeLink(b);
		if (!RopeCanCollide(linkA, b.GetID()) || !RopeCanCollide(linkB, a.GetID()))
			return false;
		if (linkA != nullptr && linkB != nullptr && linkA->rope == linkB->rope) {
			const auto separation = std::max(linkA->index, linkB->index) - std::min(linkA->index, linkB->index);
			return separation > linkA->rope->neighborExclusion;
		}
		return true;
	}
};

const RopeCollisionFilter sRopeCollisionFilter;
