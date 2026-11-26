[[vk::binding(0, 0)]] StructuredBuffer<uint> inputValues;
[[vk::binding(1, 0)]] RWStructuredBuffer<uint> outputValues;

[numthreads(16, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint count, stride;
    outputValues.GetDimensions(count, stride);
    if (id.x < count) {
        outputValues[id.x] = inputValues[id.x] * 3u + outputValues[id.x];
    }
}
