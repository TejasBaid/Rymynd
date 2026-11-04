#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// A single expanding ripple, like a drop landing on still water.
/// `time` is seconds since the drop. Brightness follows the wave slightly, so the ring catches the light.
[[ stitchable ]]
half4 Ripple(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float time,
    float amplitude,
    float frequency,
    float decay,
    float speed
) {
    float distance = length(position - origin);
    float delay = distance / speed;
    float t = max(0.0, time - delay);

    float rippleAmount = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 direction = distance > 0.0 ? normalize(position - origin) : float2(0.0);
    float2 samplePosition = position + rippleAmount * direction;

    half4 color = layer.sample(samplePosition);
    color.rgb += 0.18 * (rippleAmount / max(amplitude, 0.001)) * color.a;
    return color;
}
