/***************************************************************************
 # ReSTIR DI - Stage 4: final shading (Falcor plumbing, complete)
 #
 # Shade the pixel with the single sample left in the final reservoir. (notes 2.3.3 step 5)
 #
 #   L = f_r(y) * cos * L_e(y) * V(y) * r.W
 #
 # Resampling used a cheap BRDF for p_hat, but here we reload the real Falcor material
 # from the VBuffer and evaluate it properly. r.W stands in for 1/p(y), so there is no
 # separate pdf division.
 **************************************************************************/
import LoadShadingData;
import Resampling;
import SurfaceData;
import Params;
import Utils.Sampling.TinyUniformSampleGenerator;
import Utils.Color.ColorHelpers;
import Utils.Debug.PixelDebug;

ConstantBuffer<ReSTIRDIParams> gParams;
Texture2D<PackedHitInfo> gVBuffer;
StructuredBuffer<SurfaceData> gSurfaceData;
StructuredBuffer<Reservoir> gReservoirs;

RWTexture2D<float4> gColor;
RWTexture2D<float4> gDebug;

#define is_valid(name) (is_valid_##name != 0)

static const bool kUseEnvBackground = USE_ENV_BACKGROUND;

/** Map an integer index to an easily distinguishable color. Debug only. */
float3 indexToColor(uint i)
{
    uint h = i * 2654435761u;
    return float3(((h >> 0) & 0xff) / 255.f, ((h >> 8) & 0xff) / 255.f, ((h >> 16) & 0xff) / 255.f);
}

float3 evalDebugOutput(const SurfaceData surface, const Reservoir r, const float3 color)
{
    switch ((DebugOutput)gParams.debugOutput)
    {
    case DebugOutput::ReservoirM:
        // Normalize M to roughly 0..512 and show it as grayscale.
        return float3(saturate(r.M / 512.f));
    case DebugOutput::ReservoirW:
        return float3(saturate(r.W));
    case DebugOutput::TargetFunction:
        return float3(saturate(evalTargetFunction(surface, r.y)));
    case DebugOutput::SelectedLightIndex:
        return r.y.isValid() ? indexToColor(r.y.index + (r.y.type << 24)) : float3(0.f);
    case DebugOutput::TemporalReuseMask:
        return (r.flags & Reservoir::kFlagTemporalReuse) != 0 ? float3(0.f, 1.f, 0.f) : float3(1.f, 0.f, 0.f);
    default:
        return color;
    }
}

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const uint2 pixel = dispatchThreadId.xy;
    if (any(pixel >= gParams.frameDim))
        return;

    printSetPixel(pixel);

    const uint idx = pixel.y * gParams.frameDim.x + pixel.x;
    const SurfaceData surface = gSurfaceData[idx];
    const Reservoir r = gReservoirs[idx];

    float3 color = float3(0.f);

    ShadingData sd;
    if (loadShadingData(pixel, gParams.frameDim, gScene.camera, gVBuffer, sd))
    {
        let lod = ExplicitLodTextureSampler(0.f);
        let hints = getMaterialInstanceHints();
        let mi = gScene.materials.getMaterialInstance(sd, lod, hints);
        let bsdfProperties = mi.getProperties(sd);

        // Emission of the surface itself.
        color += bsdfProperties.emission;

        if (r.isValid())
        {
            EvaluatedLightSample els;
            if (evalLightSample(surface.posW, r.y, els))
            {
                bool visible = true;
                if (gParams.useFinalVisibility != 0)
                    visible = traceShadowRay(surface.posW, els.dir, els.distance);

                if (visible)
                {
                    TinyUniformSampleGenerator sg = TinyUniformSampleGenerator(pixel, gParams.frameCount + 0x3000);
                    // mi.eval() returns f_r * cos. els.Li is the raw radiance.
                    color += mi.eval(sd, els.dir, sg) * els.Li * r.W;
                }
            }
        }
    }
    else if (kUseEnvBackground)
    {
        const float3 dir = gScene.camera.computeRayPinhole(pixel, gParams.frameDim).dir;
        color = gScene.envMap.eval(dir);
    }

    gColor[pixel] = float4(color, 1.f);

    if (is_valid(gDebug))
        gDebug[pixel] = float4(evalDebugOutput(surface, r, color), 1.f);
}
