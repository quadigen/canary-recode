#+build !js
package extensions

import classes "../classes"
import "core:fmt"
import "core:testing"
import "core:time"

batch_test_calls: u64
batch_test_instances: u64
batch_test_valid: bool
batch_test_step :: proc "c" (
	ext: KNE_Extension,
	instance: KNE_Instance,
	dt: f64,
) {batch_test_calls += 1; batch_test_instances += 1; if kne_instances_get_user_data(
		   ext,
		   instance,
	   ) !=
	   instance {batch_test_valid = false}}
batch_test_batch :: proc "c" (
	ext: KNE_Extension,
	entries: [^]KNE_Batch_Instance,
	count: uintptr,
	dt: f64,
) {
	batch_test_calls += 1; batch_test_instances += u64(count)
	if count == 0 || count > KNE_BATCH_MAX_INSTANCES {batch_test_valid = false}
	for i in 0 ..< int(count) {if entries[i].instance == nil || entries[i].user_data != entries[i].instance {batch_test_valid = false}}
}
@(test)
batch_dispatch_is_bounded_and_preserves_legacy_callbacks :: proc(t: ^testing.T) {
	N :: 4096
	objects := make([]classes.Object, N); defer delete(objects)
	descriptor: classes.Class_Descriptor
	defer delete(descriptor.instances)
	ctx: Context
	ctx.instance_data = make(map[^classes.Object]rawptr); defer delete(ctx.instance_data)
	desc := KNE_Extension_Desc {
		abi_major = KNE_ABI_MAJOR,
		abi_minor = KNE_ABI_MINOR,
	}
	record := Extension_Record {
		state = .Running,
		desc  = &desc,
		ctx   = &ctx,
	}
	registration := Class_Registration {
		descriptor = &descriptor,
		extension  = &record,
	}
	defer delete(registration.step_snapshot)
	append(&record.classes, &registration); defer delete(record.classes)
	append(&ctx.records, &record); defer delete(ctx.records)
	for &object in objects {append(&descriptor.instances, &object); ctx.instance_data[&object] = rawptr(&object)}
	objects[7].destroyed = true
	registration.desc.step = batch_test_step
	batch_test_calls = 0; batch_test_instances = 0; batch_test_valid = true
	start := time.now()
	for _ in 0 ..< 100 {Step(&ctx, 1.0 / 60.0)}
	scalar_time := time.since(start)
	testing.expect(t, batch_test_calls == 100 * (N - 1), "legacy one callback per live object")
	testing.expect(
		t,
		ctx.step_calls == N - 1 && ctx.batch_calls == 0,
		"legacy dispatch statistics",
	)
	testing.expect(t, batch_test_valid, "scalar callback receives identical user data")
	registration.desc.step_batch = batch_test_batch
	batch_test_calls = 0; batch_test_instances = 0; batch_test_valid = true
	start = time.now()
	for _ in 0 ..< 100 {Step(&ctx, 1.0 / 60.0)}
	batch_time := time.since(start)
	testing.expect(
		t,
		batch_test_calls == 400 && batch_test_instances == 100 * (N - 1),
		"4095 live objects dispatched in four batches",
	)
	testing.expect(
		t,
		batch_test_valid,
		"callback views contain matching user data and bounded counts",
	)
	testing.expect(
		t,
		ctx.step_calls == 0 && ctx.batch_calls == 4 && ctx.stepped_instances == N - 1,
		"batch replaces scalar step",
	)
	fmt.printf(
		"KNE_BATCH_BENCH objects=%d frames=100 scalar_calls=%d batch_calls=%d scalar_ms=%.3f batch_ms=%.3f\n",
		N - 1,
		100 * (N - 1),
		batch_test_calls,
		f64(scalar_time) / f64(time.Millisecond),
		f64(batch_time) / f64(time.Millisecond),
	)
}

@(test)
batch_descriptor_respects_legacy_prefix_and_extension_version :: proc(t: ^testing.T) {
	desc := KNE_Class_Desc {
		size       = u32(offset_of(KNE_Class_Desc, step_batch)),
		version    = KNE_ABI_MAJOR,
		step       = batch_test_step,
		step_batch = batch_test_batch,
	}
	legacy := kne_class_desc_copy(&desc, 2)
	testing.expect(
		t,
		legacy.step == batch_test_step && legacy.step_batch == nil,
		"old short descriptor does not expose appended callback",
	)
	desc.size = u32(size_of(KNE_Class_Desc))
	old_extension := kne_class_desc_copy(&desc, 1)
	testing.expect(
		t,
		old_extension.step_batch == nil,
		"ABI 3.1 extension retains scalar callback contract",
	)
	modern := kne_class_desc_copy(&desc, 2)
	testing.expect(
		t,
		modern.step_batch == batch_test_batch && modern.step == batch_test_step,
		"ABI 3.2 extension explicitly opts into batch",
	)
	desc.size = 8
	invalid := kne_class_desc_copy(&desc, 2)
	testing.expect(
		t,
		invalid.step == nil && invalid.step_batch == nil,
		"invalid descriptor prefix is not read",
	)
}
