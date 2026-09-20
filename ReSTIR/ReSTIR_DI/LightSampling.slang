/***************************************************************************
 # ReSTIR DI - generating and re-evaluating light samples
 #
 # This file is Falcor plumbing, so it is fully implemented. The ReSTIR core lives
 # in Reservoir.slang / TargetFunction.slang / Resampling.slang.
 #
 # [KEY DESIGN POINT] A reservoir does not store a point on a light. It stores the
 # pair (light index, the random numbers uv used to sample it). Stored that way, the
 # exact same point on the light can be reconstructed from any other shading point.
 # Spatiotemporal reuse needs that property in order to re-evaluate a neighbor's
 # sample at your own pixel.
 **************************************************************************/
__exported import Scene.Scene;
import Scene.RaytracingInline;
import Rendering.Lights.LightHelpers;
import Rendering.Lights.EmissiveLightSamplerHelpers;
import Utils.Sampling.SampleGeneratorInterface;
import Utils.Color.ColorHelpers;
import Params;

static const uint kLightTypeInvalid = 0;
/// Falcor analytic light (point / directional / rect / sphere / disc / distant).
static const uint kLightTypeAnalytic = 1;
/// Emissive triangle (mesh light).
static const uint kLightTypeEmissive = 2;

/**
 * The light sample stored in a reservoir. This alone is enough to re-evaluate the
 * sample at any shading point. 16 bytes.
 */
struct LightSample
{
    uint type;   ///< One of kLightType*.
    uint index;  ///< Analytic light index, or emissive triangle index.
    float2 uv;   ///< The two uniform random numbers used to pick the point on the light.

    static LightSample createInvalid()
    {
        LightSample ls = {};
        ls.type = kLightTypeInvalid;
        return ls;
    }

    bool isValid() { return type != kLightTypeInvalid; }
};

/** The result of evaluating a LightSample at a particular shading point. */
struct EvaluatedLightSample
{
    float3 posW;    ///< Point on the light in world space. For a delta light, the light position.
    float3 normalW; ///< Light surface normal. Zero for a delta light.
    float3 dir;     ///< Normalized direction from the shading point to the light.
    float distance; ///< Distance from the shading point to the light.
    float3 Li;      ///< Incident radiance at the shading point, ignoring shadowing and NOT divided by any pdf.
    float pdf;      ///< Solid-angle density of picking this point ON the light. Excludes the light selection probability.
};

/** Total number of light candidates in the scene (analytic + emissive triangles). */
uint getTotalLightCount()
{
    return gScene.getLightCount() + gScene.lightCollection.getTriangleCount();
}

/**
 * Probability of picking one particular light. We use the simplest possible choice,
 * a uniform pick. (notes 2.2.2 argues that with a large enough M, ReSTIR does not
 * need a fancy acceleration structure for light selection.)
 */
float getLightSelectionPdf()
{
    uint total = getTotalLightCount();
    return total > 0 ? 1.f / (float)total : 0.f;
}

/**
 * Generate one candidate light sample: pick a light uniformly and draw the random
 * numbers uv used to place the point on it. The actual point is reconstructed later
 * in evalLightSample().
 */
LightSample generateLightSample<S : ISampleGenerator>(inout S sg)
{
    const uint lightCount = gScene.getLightCount();
    const uint triangleCount = gScene.lightCollection.getTriangleCount();
    const uint total = lightCount + triangleCount;

    if (total == 0)
        return LightSample::createInvalid();

    LightSample ls;
    uint i = min((uint)(sampleNext1D(sg) * total), total - 1);
    if (i < lightCount)
    {
        ls.type = kLightTypeAnalytic;
        ls.index = i;
    }
    else
    {
        ls.type = kLightTypeEmissive;
        ls.index = i - lightCount;
    }
    ls.uv = sampleNext2D(sg);
    return ls;
}

/**
 * Re-evaluate a stored LightSample at an arbitrary shading point. This is what lets
 * spatiotemporal reuse score a neighbor's sample from the current pixel.
 *
 * @return True for a valid sample. False for e.g. the back side of a light.
 */
bool evalLightSample(const float3 shadingPosW, const LightSample ls, out EvaluatedLightSample els)
{
    els = {};

    if (ls.type == kLightTypeEmissive)
    {
        TriangleLightSample tls;
        if (!sampleTriangle(shadingPosW, ls.index, ls.uv, tls))
            return false;

        els.posW = tls.posW;
        els.normalW = tls.normalW;
        els.dir = tls.dir;
        els.distance = tls.distance;
        els.Li = tls.Le; // Emitted radiance of the triangle light.
        els.pdf = tls.pdf;
        return els.pdf > 0.f;
    }
    else if (ls.type == kLightTypeAnalytic)
    {
        const LightData light = gScene.getLight(ls.index);

        AnalyticLightSample als;
        bool valid = false;
        switch (light.type)
        {
        case LightType::Point:
            valid = samplePointLight(shadingPosW, light, als);
            break;
        case LightType::Directional:
            valid = sampleDirectionalLight(shadingPosW, light, als);
            break;
        case LightType::Rect:
            valid = sampleRectAreaLight(shadingPosW, light, ls.uv, als);
            break;
        case LightType::Sphere:
            valid = sampleSphereAreaLight(shadingPosW, light, ls.uv, als);
            break;
        case LightType::Disc:
            valid = sampleDiscAreaLight(shadingPosW, light, ls.uv, als);
            break;
        case LightType::Distant:
            valid = sampleDistantLight(shadingPosW, light, ls.uv, als);
            break;
        }
        if (!valid)
            return false;

        els.posW = als.posW;
        els.normalW = als.normalW;
        els.dir = als.dir;
        els.distance = als.distance;
        // Falcor's AnalyticLightSample.Li is already divided by the pdf. We want the
        // raw radiance here, so multiply the pdf back in. Delta lights (point,
        // directional) have pdf == 1, so they are unaffected.
        els.Li = als.Li * als.pdf;
        els.pdf = als.pdf;
        return els.pdf > 0.f;
    }

    return false;
}

/** Shadow ray. Returns false if the light point is occluded. */
bool traceShadowRay(const float3 originW, const float3 dirW, const float distance)
{
    SceneRayQuery<1> rayQuery;
    const Ray ray = Ray(originW, dirW, 0.f, max(0.f, distance - 1e-3f));
    return rayQuery.traceVisibilityRay(ray);
}
