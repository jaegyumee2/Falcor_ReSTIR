/***************************************************************************
 # ReSTIR DI - per-pixel surface data
 #
 # Falcor plumbing, fully implemented.
 #
 # Why this needs its own buffer:
 #  - Spatial reuse: you need the neighbor's surface in order to evaluate p_hat from
 #    the neighbor's point of view, which the MIS bias correction requires.
 #  - Temporal reuse: last frame's VBuffer is gone. So every frame we write a compact
 #    surface record into a buffer and read it back next frame (ping-pong).
 #
 # Note: p_hat only drives resampling decisions, so it uses a cheap diffuse + GGX
 # model instead of the full Falcor material. Final shading (FinalShading.cs.slang)
 # reloads the real material from the VBuffer and evaluates it properly.
 **************************************************************************/
#include "Utils/Math/MathConstants.slangh"

__exported import Scene.Scene;
import Rendering.Materials.IsotropicGGX;
import Utils.Math.MathHelpers;

/** The minimum surface information resampling needs. */
struct SurfaceData
{
    float3 posW;     ///< Shading point, already offset so it can be used directly as a shadow ray origin.
    float viewDepth; ///< Distance from the camera. Used to accept or reject spatiotemporal neighbors.

    float3 normalW; ///< Shading normal.
    float roughness;

    float3 viewW; ///< Normalized direction from the shading point to the camera.
    float _pad0;

    float3 diffuse; ///< Diffuse albedo.
    float _pad1;

    float3 specular; ///< Specular reflectance (F0).
    float _pad2;

    static SurfaceData createInvalid()
    {
        SurfaceData s = {};
        s.viewDepth = -1.f;
        return s;
    }

    bool isValid() { return viewDepth >= 0.f; }
};

/**
 * Simple BRDF used for resampling. Returns f_r(wi, wo) * cos(theta_i), i.e. the cosine
 * term is already folded in, the same convention as Falcor's mi.eval().
 */
float3 evalSimpleBrdf(const SurfaceData surface, const float3 L)
{
    const float3 N = surface.normalW;
    const float3 V = surface.viewW;

    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    if (NdotL <= 0.f || NdotV <= 0.f)
        return float3(0.f);

    // Lambertian diffuse.
    float3 diffuse = surface.diffuse * M_1_PI;

    // Isotropic GGX specular (Smith correlated masking-shadowing + Schlick Fresnel).
    const float3 H = normalize(V + L);
    float NdotH = saturate(dot(N, H));
    float LdotH = saturate(dot(L, H));

    float alpha = max(surface.roughness * surface.roughness, 1e-3f);
    float D = evalNdfGGX(alpha, NdotH);
    float G = evalMaskingSmithGGXCorrelated(alpha, NdotV, NdotL);
    float3 F = surface.specular + (1.f - surface.specular) * pow(saturate(1.f - LdotH), 5.f);

    // f_spec = D*G*F / (4 * NdotV * NdotL), so multiplying by the cosine cancels NdotL.
    float3 specular = D * G * F / (4.f * NdotV);

    return diffuse * NdotL + specular;
}

/**
 * Decide whether a surface may be accepted as a spatiotemporal neighbor
 * (geometric similarity test). Reusing across very different normals or depths
 * produces artifacts.
 */
bool isSurfaceSimilar(const SurfaceData a, const SurfaceData b, const float normalThreshold, const float depthThreshold)
{
    if (!a.isValid() || !b.isValid())
        return false;
    if (dot(a.normalW, b.normalW) < normalThreshold)
        return false;
    if (abs(a.viewDepth - b.viewDepth) > depthThreshold * max(a.viewDepth, 1e-4f))
        return false;
    return true;
}
