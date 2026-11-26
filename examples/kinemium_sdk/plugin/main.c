#include "kinemium_plugin.h"
#include <stdint.h>
#include <stddef.h>
#include <string.h>

typedef struct { double amount; bool critical; } NativeDamage;

static bool damage_construct(Kinemium_Context *ctx, void *data, uint32_t count,
                             const Kinemium_Value *arguments) {
    (void)ctx;
    if (count < 2 || arguments[0].kind != KINEMIUM_VALUE_NUMBER ||
        arguments[1].kind != KINEMIUM_VALUE_BOOLEAN) return false;
    NativeDamage *damage = data;
    damage->amount = arguments[0].number;
    damage->critical = arguments[1].boolean;
    return true;
}

static bool damage_double(Kinemium_Context *ctx, void *data, uint32_t count,
                          const Kinemium_Value *args, Kinemium_Value *out) {
    (void)ctx;
    (void)count;
    (void)args;
    out->kind = KINEMIUM_VALUE_NUMBER;
    out->number = ((NativeDamage *)data)->amount * 2.0;
    return true;
}

static int32_t damage_encode(Kinemium_Context *ctx, void *data, void *buffer,
                             uint64_t capacity, uint64_t *required_size) {
    (void)ctx;
    if (!required_size || !data) return -1;
    *required_size = 9;
    if (!buffer || capacity < 9) return 0;
    const NativeDamage *damage = data;
    uint64_t bits;
    memcpy(&bits, &damage->amount, sizeof(bits));
    uint8_t *bytes = buffer;
    for (uint32_t i = 0; i < 8; ++i) {
        bytes[i] = (uint8_t)((bits >> (8 * i)) & 0xff);
    }
    bytes[8] = damage->critical ? 1 : 0;
    return 1;
}

static bool damage_add(Kinemium_Context *ctx, const void *left, const void *right, void *output) {
    (void)ctx;
    const NativeDamage *a = left;
    const NativeDamage *b = right;
    NativeDamage *result = output;
    result->amount = a->amount + b->amount;
    result->critical = a->critical || b->critical;
    return true;
}

static bool damage_negate(Kinemium_Context *ctx, const void *left, const void *right, void *output) {
    (void)ctx;
    (void)right;
    const NativeDamage *input = left;
    NativeDamage *result = output;
    result->amount = -input->amount;
    result->critical = input->critical;
    return true;
}

static bool damage_equal(Kinemium_Context *ctx, const void *left, const void *right) {
    (void)ctx;
    const NativeDamage *a = left;
    const NativeDamage *b = right;
    return a->amount == b->amount && a->critical == b->critical;
}

static const char *damage_to_string(Kinemium_Context *ctx, const void *data) {
    (void)ctx;
    (void)data;
    return "NativeDamageInfo";
}

static bool damage_decode(Kinemium_Context *ctx, void *data, const void *buffer, uint64_t size) {
    (void)ctx;
    if (!data || !buffer || size != 9) return false;
    const uint8_t *bytes = buffer;
    uint64_t bits = 0;
    for (uint32_t i = 0; i < 8; ++i) {
        bits |= ((uint64_t)bytes[i]) << (8 * i);
    }
    NativeDamage *damage = data;
    memcpy(&damage->amount, &bits, sizeof(bits));
    damage->critical = bytes[8] != 0;
    return true;
}

typedef struct { double value; } NativeCounter;
typedef struct { double temperature; } NativeWeather;

static void counter_construct(Kinemium_Context *ctx, void *data) {
    (void)ctx;
    ((NativeCounter *)data)->value = 10.0;
}

static bool counter_increment(Kinemium_Context *ctx, void *data, uint32_t count,
                              const Kinemium_Value *args, Kinemium_Value *out) {
    (void)ctx;
    NativeCounter *counter = data;
    double amount = (count > 0 && args[0].kind == KINEMIUM_VALUE_NUMBER) ? args[0].number : 1.0;
    counter->value += amount;
    out->kind = KINEMIUM_VALUE_NUMBER;
    out->number = counter->value;
    return true;
}

static bool counter_get(Kinemium_Context *ctx, void *data,
                        const char *name, Kinemium_Value *result) {
    (void)ctx;
    if (strcmp(name, "SquaredValue") != 0) return false;
    double value = ((NativeCounter *)data)->value;
    result->kind = KINEMIUM_VALUE_NUMBER;
    result->number = value * value;
    return true;
}

static bool counter_set(Kinemium_Context *ctx, void *data,
                        const char *name, const Kinemium_Value *input) {
    (void)ctx;
    if (strcmp(name, "Value") != 0 || input->kind != KINEMIUM_VALUE_NUMBER) return false;
    double value = input->number;
    ((NativeCounter *)data)->value = value > 100 ? 100 : value;
    return true;
}

static void counter_batch(Kinemium_Context *ctx,
                          Kinemium_BatchInstance *instances,
                          uint32_t count, double delta_seconds) {
    (void)ctx;
    for (uint32_t i = 0; i < count; ++i) {
        ((NativeCounter *)instances[i].data)->value += delta_seconds;
    }
}

static void weather_construct(Kinemium_Context *ctx, void *data) {
    (void)ctx;
    ((NativeWeather *)data)->temperature = 26.0;
}

static Kinemium_Handle created_part;
static uint64_t tick_count;

static bool native_sum(void *user_data, uint32_t count, const Kinemium_Value *arguments, Kinemium_Value *out) {
    (void)user_data;
    if (count != 2 || !out ||
        arguments[0].kind != KINEMIUM_VALUE_NUMBER ||
        arguments[1].kind != KINEMIUM_VALUE_NUMBER) {
        return false;
    }
    out->kind = KINEMIUM_VALUE_NUMBER;
    out->number = arguments[0].number + arguments[1].number;
    return true;
}

static bool on_load(Kinemium_Context *ctx) {
    if (!Kinemium_ContextIsBorrowed(ctx)) return false;
    if (Kinemium_ContextGetPlugin(ctx) == 0) return false;

    Kinemium_Handle workspace = Kinemium_HandleService(ctx, "Workspace");
    if (!workspace) return false;

    created_part = Kinemium_HandleCreateInstance(ctx, "Part");
    if (!created_part ||
        !Kinemium_HandleSetDynamicString(ctx, created_part, "Name", "NativePluginPart") ||
        !Kinemium_HandleSetDynamicBoolean(ctx, created_part, "Anchored", true) ||
        !Kinemium_HandleSetParent(ctx, created_part, workspace)) {
        return false;
    }

    Kinemium_ClassDesc counter = Kinemium_Class("NativeCounter", "Instance", sizeof(NativeCounter));
    counter.on_construct = counter_construct;
    counter.on_batch_step = counter_batch;
    counter.on_get = counter_get;
    counter.on_set = counter_set;
    if (!Kinemium_ClassProperty(&counter, "Value", KINEMIUM_NUMBER, offsetof(NativeCounter, value)) ||
        !Kinemium_ClassMethod(&counter, "Increment", counter_increment) ||
        !Kinemium_RegisterClass(ctx, &counter)) return false;

    Kinemium_ServiceDesc weather = Kinemium_Service("NativeWeatherService", sizeof(NativeWeather));
    weather.on_construct = weather_construct;
    if (!Kinemium_ClassProperty(&weather, "Temperature", KINEMIUM_NUMBER, offsetof(NativeWeather, temperature)) ||
        !Kinemium_RegisterService(ctx, &weather)) return false;

    Kinemium_DatatypeDesc damage = Kinemium_Datatype("NativeDamageInfo", sizeof(NativeDamage));
    damage.flags = KINEMIUM_DATATYPE_PERSISTABLE | KINEMIUM_DATATYPE_REPLICATED;
    damage.wire_version = 1;
    damage.on_construct = damage_construct;
    damage.on_encode = damage_encode;
    damage.on_decode = damage_decode;
    damage.on_add = damage_add;
    damage.on_negate = damage_negate;
    damage.on_equal = damage_equal;
    damage.on_string = damage_to_string;
    if (!Kinemium_DatatypeField(&damage, "Amount", KINEMIUM_NUMBER, offsetof(NativeDamage, amount)) ||
        !Kinemium_DatatypeField(&damage, "Critical", KINEMIUM_BOOLEAN, offsetof(NativeDamage, critical)) ||
        !Kinemium_DatatypeMethod(&damage, "Double", damage_double) ||
        !Kinemium_RegisterDatatype(ctx, &damage)) return false;

    Kinemium_DatatypeDesc legacy = Kinemium_Datatype("NativeLegacyScalar", sizeof(double));
    legacy.size = (uint32_t)offsetof(Kinemium_DatatypeDesc, on_add);
    if (!Kinemium_DatatypeField(&legacy, "Value", KINEMIUM_NUMBER, 0) ||
        !Kinemium_RegisterDatatype(ctx, &legacy)) return false;

    return Kinemium_RegisterNativeFunction(ctx, "NativePluginSum", native_sum, NULL) &&
           Kinemium_RegisterLibraryFunction(ctx, "NativePluginMath", "Sum", native_sum, NULL);
}

static bool on_start(Kinemium_Context *ctx) {
    return Kinemium_RunLuau(ctx,
        "assert(NativePluginSum(9,4)==13 and NativePluginMath.Sum(9,4)==13); "
        "local d=NativeDamageInfo.new(50,true); "
        "assert(typeof(d)=='NativeDamageInfo' and d.Amount==50 and d.Critical); "
        "d.Amount=70; assert(d:Double()==140); "
        "local sum=d+NativeDamageInfo.new(5,false); assert(sum.Amount==75 and sum.Critical); "
        "local neg=-sum; assert(neg.Amount==-75); "
        "assert(NativeDamageInfo.new(50,true)==NativeDamageInfo.new(50,true)); "
        "assert(tostring(sum)=='NativeDamageInfo'); "
        "local legacy=NativeLegacyScalar.new(); legacy.Value=5; assert(legacy.Value==5)");
}

static void on_update(Kinemium_Context *ctx, double dt) {
    (void)dt;
    tick_count++;
    Kinemium_SetGlobalNumber(ctx, "NativePluginTicks", (double)tick_count);
}

static void on_stop(Kinemium_Context *ctx) {
    Kinemium_SetGlobalBoolean(ctx, "NativePluginStopped", true);
}

static void on_unload(Kinemium_Context *ctx) {
    if (created_part) {
        Kinemium_HandleDestroy(ctx, created_part);
        created_part = 0;
    }
}

static const Kinemium_PluginDescriptor description = {
    .size = sizeof(Kinemium_PluginDescriptor),
    .abi_major = KINEMIUM_PLUGIN_ABI_MAJOR,
    .abi_minor = KINEMIUM_PLUGIN_ABI_MINOR,
    .id = "native.example",
    .name = "Native Example",
    .version = "1.0.0",
    .on_load = on_load,
    .on_start = on_start,
    .on_update = on_update,
    .on_stop = on_stop,
    .on_unload = on_unload
};

const Kinemium_PluginDescriptor *Kinemium_PluginEntry(void) {
    return &description;
}
