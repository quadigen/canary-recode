namespace {
struct SoftContactPoint {
	JPH::Vec3 position, velocity;
	float inverseMass;
};

struct SoftContactFace {
	JPH::AABox bounds;
	uint32_t vertices[3];
};

struct SoftContactNode {
	JPH::AABox bounds;
	uint32_t start, end, right = 0;
};

struct SoftContactBody {
	JPH::Body *body = nullptr;
	JPH::AABox bounds;
	std::vector<SoftContactPoint> points;
	std::vector<SoftContactFace> faces;
	std::vector<SoftContactNode> tree;
	float radius = 0;
	bool closed = false, changed = false;

	uint32_t buildNode(uint32_t start, uint32_t end) {
		const uint32_t index = uint32_t(tree.size());
		JPH::AABox box;
		for (uint32_t i = start; i < end; ++i) box.Encapsulate(faces[i].bounds);
		tree.push_back({box, start, end});
		if (end - start <= 6) return index;
		const int axis = box.GetExtent().GetHighestComponentIndex();
		const uint32_t middle = start + (end - start) / 2;
		std::nth_element(faces.begin() + start, faces.begin() + middle, faces.begin() + end,
			[axis](const SoftContactFace &a, const SoftContactFace &b) {
				return a.bounds.GetCenter()[axis] < b.bounds.GetCenter()[axis];
			});
		buildNode(start, middle);
		tree[index].right = buildNode(middle, end);
		return index;
	}

	void prepare(float dt) {
		if (!tree.empty()) return;
		auto *motion = static_cast<JPH::SoftBodyMotionProperties *>(body->GetMotionProperties());
		const auto rotation = body->GetRotation();
		const auto center = JPH::Vec3(body->GetCenterOfMassPosition());
		radius = motion->GetVertexRadius();
		points.reserve(motion->GetVertices().size());
		for (const auto &vertex : motion->GetVertices()) {
			points.push_back({center + rotation * vertex.mPosition, rotation * vertex.mVelocity, vertex.mInvMass});
		}
		faces.reserve(motion->GetFaces().size());
		for (const auto &face : motion->GetFaces()) {
			SoftContactFace target{{}, {face.mVertex[0], face.mVertex[1], face.mVertex[2]}};
			for (uint32_t i : target.vertices) {
				target.bounds.Encapsulate(points[i].position);
				target.bounds.Encapsulate(points[i].position + dt * points[i].velocity);
			}
			faces.push_back(target);
		}
		if (!faces.empty()) buildNode(0, uint32_t(faces.size()));
	}
};

struct SoftContact {
	const SoftContactFace *face = nullptr;
	JPH::Vec3 normal;
	float weights[3];
	float time = FLT_MAX;
	float penetration = 0;
};

// Conservative advancement along the particle and the moving triangle.
void soft_contact_face(
	const SoftContactPoint &point, const SoftContactBody &target, const SoftContactFace &face,
	float radius, float dt, SoftContact &best) {
	float time = 0;
	for (int attempt = 0; attempt < 6 && time <= dt && time <= best.time; ++attempt) {
		const auto p = point.position + time * point.velocity;
		JPH::Vec3 v[3];
		for (int i = 0; i < 3; ++i) {
			const auto &corner = target.points[face.vertices[i]];
			v[i] = corner.position + time * corner.velocity - p;
		}
		uint32_t feature;
		const auto closest = JPH::ClosestPoint::GetClosestPointOnTriangle(v[0], v[1], v[2], feature);
		const float distance = closest.Length();
		float weights[3];
		JPH::ClosestPoint::GetBaryCentricCoordinates(
			v[0] - closest, v[1] - closest, v[2] - closest, weights[0], weights[1], weights[2]);
		JPH::Vec3 surfaceVelocity = JPH::Vec3::sZero();
		for (int i = 0; i < 3; ++i) surfaceVelocity += weights[i] * target.points[face.vertices[i]].velocity;
		const auto relative = point.velocity - surfaceVelocity;
		const auto faceNormal = (v[1] - v[0]).Cross(v[2] - v[0]).NormalizedOr(JPH::Vec3::sZero());
		auto normal = distance > 1.0e-6f ? -closest / distance : faceNormal;
		if (target.closed && distance <= radius && normal.Dot(faceNormal) < 0) normal = faceNormal;
		else if (!target.closed && distance <= 1.0e-6f && relative.Dot(normal) > 0) normal = -normal;
		const float speed = relative.Dot(normal);
		if (distance <= radius + 1.0e-5f) {
			const float depth = radius - distance;
			if (speed >= 0 && depth <= 0) return;
			if (time == best.time && depth <= best.penetration) return;
			best = {&face, normal, {weights[0], weights[1], weights[2]}, time, depth};
			return;
		}
		if (speed >= -1.0e-5f) return;
		time += (distance - radius) / -speed;
	}
}

void soft_contact_query(
	const SoftContactPoint &point, const SoftContactBody &target, uint32_t index,
	const JPH::AABox &sweep, float radius, float dt, SoftContact &best) {
	const auto &node = target.tree[index];
	if (!node.bounds.Overlaps(sweep)) return;
	if (node.right != 0) {
		soft_contact_query(point, target, index + 1, sweep, radius, dt, best);
		soft_contact_query(point, target, node.right, sweep, radius, dt, best);
		return;
	}
	for (uint32_t i = node.start; i < node.end; ++i) {
		const auto &face = target.faces[i];
		if (face.bounds.Overlaps(sweep)) soft_contact_face(point, target, face, radius, dt, best);
	}
}

void soft_contact_solve(SoftContactBody &source, SoftContactBody &target, float dt) {
	if (target.tree.empty()) return;
	const float radius = std::max(0.005f, source.radius + target.radius);
	for (auto &point : source.points) {
		JPH::AABox sweep(point.position, point.position);
		sweep.Encapsulate(point.position + dt * point.velocity);
		sweep.ExpandBy(JPH::Vec3::sReplicate(radius));
		SoftContact contact;
		soft_contact_query(point, target, 0, sweep, radius, dt, contact);
		if (!contact.face) continue;
		float inverseMass = point.inverseMass;
		auto relative = point.velocity;
		for (int i = 0; i < 3; ++i) {
			const auto &corner = target.points[contact.face->vertices[i]];
			inverseMass += corner.inverseMass * contact.weights[i] * contact.weights[i];
			relative -= contact.weights[i] * corner.velocity;
		}
		if (inverseMass <= 0) continue;
		const float bias = 0.35f * std::max(0.0f, contact.penetration) / dt;
		const float impulse = (bias - relative.Dot(contact.normal)) / inverseMass;
		if (impulse <= 0) continue;
		const auto change = impulse * contact.normal;
		point.velocity += point.inverseMass * change;
		for (int i = 0; i < 3; ++i) {
			auto &corner = target.points[contact.face->vertices[i]];
			corner.velocity -= (corner.inverseMass * contact.weights[i]) * change;
		}
		source.changed = target.changed = true;
	}
}

bool soft_contact_rigid(SoftContactBody &soft, JPH::Body &rigid, const JPH::AABox &sweep, float dt, bool &contact) {
	const auto *shape = rigid.GetShape();
	const auto center = rigid.GetCenterOfMassPosition();
	const auto origin = JPH::Vec3(center);
	const auto velocity = rigid.GetLinearVelocity();
	const auto transform = JPH::Mat44::sRotation(rigid.GetRotation());
	const auto unit = JPH::Vec3::sOne();
	const auto identity = JPH::Mat44::sIdentity();
	JPH::ShapeCastSettings settings;
	settings.SetBackFaceMode(JPH::EBackFaceMode::CollideWithBackFaces);
	settings.mReturnDeepestPoint = true;
	settings.mExtraConvexRadius = soft.radius;
	float bestTime = FLT_MAX, bestDepth = 0, bestWeights[3]{}, bestSpeed = 0;
	const SoftContactFace *bestFace = nullptr;
	JPH::Vec3 bestNormal, bestLever;
	for (const auto &face : soft.faces) {
		if (!face.bounds.Overlaps(sweep)) continue;
		const auto &a = soft.points[face.vertices[0]];
		const auto &b = soft.points[face.vertices[1]];
		const auto &c = soft.points[face.vertices[2]];
		if ((b.position - a.position).Cross(c.position - a.position).LengthSq() < 1.0e-14f) continue;
		const JPH::Vec3 vertices[] = {a.position - origin, b.position - origin, c.position - origin};
		const JPH::TriangleShape triangle(vertices[0], vertices[1], vertices[2]);
		const auto direction = dt * ((a.velocity + b.velocity + c.velocity) / 3.0f - velocity);
		const JPH::ShapeCast cast(&triangle, unit, identity, direction);
		JPH::ClosestHitCollisionCollector<JPH::CastShapeCollector> collector;
		JPH::CollisionDispatch::sCastShapeVsShapeWorldSpace(
			cast, settings, shape, unit, {}, transform, {}, {}, collector);
		if (!collector.HadHit()) continue;
		const auto &hit = collector.mHit;
		const float depth = hit.mFraction == 0 ? hit.mPenetrationDepth : 0;
		if (hit.mFraction > bestTime || (hit.mFraction == bestTime && depth <= bestDepth)) continue;
		const auto normal = hit.mPenetrationAxis.NormalizedOr(JPH::Vec3::sZero());
		if (normal.IsNearZero()) continue;
		contact = true;
		const auto point = hit.mContactPointOn1 - hit.mFraction * direction;
		float weights[3];
		JPH::ClosestPoint::GetBaryCentricCoordinates(
			vertices[0] - point, vertices[1] - point, vertices[2] - point,
			weights[0], weights[1], weights[2]);
		float weightSum = 0;
		for (float &weight : weights) {
			weight = std::clamp(weight, 0.0f, 1.0f);
			weightSum += weight;
		}
		if (!(weightSum > 0)) continue;
		for (float &weight : weights) weight /= weightSum;
		const auto lever = hit.mContactPointOn2;
		const auto relative = weights[0] * a.velocity + weights[1] * b.velocity + weights[2] * c.velocity
			- rigid.GetPointVelocityCOM(lever);
		const float speed = relative.Dot(normal) + 0.2f * std::max(0.0f, depth - soft.radius) / dt;
		if (speed <= 0) continue;
		bestFace = &face;
		bestTime = hit.mFraction;
		bestDepth = depth;
		std::copy_n(weights, 3, bestWeights);
		bestSpeed = speed;
		bestNormal = normal;
		bestLever = lever;
	}
	if (!bestFace) return false;
	float inverseMass = 0;
	for (int i = 0; i < 3; ++i)
		inverseMass += bestWeights[i] * bestWeights[i] * soft.points[bestFace->vertices[i]].inverseMass;
	if (rigid.IsDynamic()) {
		const auto torque = bestLever.Cross(bestNormal);
		inverseMass += rigid.GetMotionProperties()->GetInverseMass()
			+ torque.Dot(rigid.GetInverseInertia().Multiply3x3(torque));
	}
	if (!(inverseMass > 0)) return false;
	const auto impulse = (bestSpeed / inverseMass) * bestNormal;
	for (int i = 0; i < 3; ++i) {
		auto &point = soft.points[bestFace->vertices[i]];
		point.velocity -= (point.inverseMass * bestWeights[i]) * impulse;
	}
	soft.changed = true;
	if (rigid.IsDynamic()) rigid.AddImpulse(impulse, center + bestLever);
	return rigid.IsDynamic();
}
}

void JPH_MeshSoftBody_Collide(
	JPH_PhysicsSystemRef system, const JPH_SoftBodyCollider *bodies, uint32_t count,
	const JPH_BodyID *rigidBodies, uint32_t rigidCount, float deltaTime,
	JPH_ObjectLayer deformableCapsuleLayer, JPH_SoftBodyContactCallback onContact, void *userData) {
	if (!system || !bodies || count == 0 || !(deltaTime > 0)) return;
	auto *physics = ToPhysicsSystem(system);
	std::vector<JPH::BodyID> ids;
	ids.reserve(size_t(count) + rigidCount);
	for (uint32_t i = 0; i < count; ++i) ids.push_back(ToBodyID(bodies[i].bodyID));
	for (uint32_t i = 0; i < rigidCount; ++i) {
		const auto id = ToBodyID(rigidBodies[i]);
		if (!id.IsInvalid()) ids.push_back(id);
	}
	std::vector<SoftContactBody> states(count);
	std::vector<JPH::BodyID> wake;
	JPH::BodyLockMultiWrite lock(physics->GetBodyLockInterface(), ids.data(), int(ids.size()));
	for (uint32_t i = 0; i < count; ++i) {
		auto *body = lock.GetBody(i);
		if (!body || !body->IsSoftBody()) continue;
		auto &state = states[i];
		state.body = body;
		state.closed = bodies[i].closedSurface != 0;
		state.bounds = body->GetWorldSpaceBounds();
		// The Jolt bounds contain the soft body. Extend them for the fastest
		// particle so a body arriving this step is included in the pair.
		const auto *motion = static_cast<const JPH::SoftBodyMotionProperties *>(body->GetMotionProperties());
		float speedSq = 0;
		for (const auto &vertex : motion->GetVertices())
			speedSq = std::max(speedSq, vertex.mVelocity.LengthSq());
		state.bounds.ExpandBy(JPH::Vec3::sReplicate(std::sqrt(speedSq) * deltaTime + motion->GetVertexRadius() + 0.005f));
	}
	for (uint32_t i = 0; i < count; ++i) {
		auto &a = states[i];
		if (!a.body) continue;
		for (uint32_t j = i + 1; j < count; ++j) {
			auto &b = states[j];
			if (!b.body || (!a.body->IsActive() && !b.body->IsActive()) || !a.bounds.Overlaps(b.bounds)) continue;
			a.prepare(deltaTime);
			b.prepare(deltaTime);
			soft_contact_solve(a, b, deltaTime);
			soft_contact_solve(b, a, deltaTime);
		}
	}
	for (size_t i = count; i < ids.size(); ++i) {
		auto *rigid = lock.GetBody(int(i));
		if (!rigid || !rigid->IsRigidBody() || rigid->IsSensor()) continue;
		auto sweep = rigid->GetWorldSpaceBounds();
		auto moved = sweep;
		moved.Translate(deltaTime * rigid->GetLinearVelocity());
		sweep.Encapsulate(moved);
		for (auto &soft : states) {
			if (!soft.body || (!soft.body->IsActive() && !rigid->IsActive() && !rigid->IsKinematic()) || !soft.bounds.Overlaps(sweep)
				|| (rigid->GetObjectLayer() != deformableCapsuleLayer &&
					!physics->GetObjectLayerPairFilter().ShouldCollide(soft.body->GetObjectLayer(), rigid->GetObjectLayer()))
				|| !soft.body->GetCollisionGroup().CanCollide(rigid->GetCollisionGroup())) continue;
			soft.prepare(deltaTime);
			bool contact = false;
			if (soft_contact_rigid(soft, *rigid, sweep, deltaTime, contact) && !rigid->IsActive()) wake.push_back(ids[i]);
			if (contact && onContact) onContact(uint32_t(&soft - states.data()), JPH_BodyID(ids[i].GetIndexAndSequenceNumber()), userData);
		}
	}
	for (auto &state : states) {
		if (!state.changed) continue;
		const auto inverseRotation = state.body->GetRotation().Conjugated();
		auto *motion = static_cast<JPH::SoftBodyMotionProperties *>(state.body->GetMotionProperties());
		auto &vertices = motion->GetVertices();
		for (size_t i = 0; i < vertices.size(); ++i)
			vertices[i].mVelocity = inverseRotation * state.points[i].velocity;
	}
	lock.ReleaseLocks();
	for (uint32_t i = 0; i < count; ++i)
		if (states[i].changed) physics->GetBodyInterface().ActivateBody(ids[i]);
	for (const auto id : wake) physics->GetBodyInterface().ActivateBody(id);
}
