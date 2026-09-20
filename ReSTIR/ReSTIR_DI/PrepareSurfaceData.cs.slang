/***************************************************************************
 # ReSTIR DI - Stage 0: prepare surface data (Falcor plumbing, complete)
 #
 # VBuffer -> compact SurfaceData buffer.
 # Next frame this same buffer serves as the "previous frame surface" for temporal reuse.
 **************************************************************************/
import LoadShadingData;
import SurfaceData;
import Params;

ConstantBuffer<ReSTIRDIParams> gParams;
Texture2D<PackedHitInfo> gVBuffer;
RWStructuredBuffer<SurfaceData> gSurfaceDataOut;

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const uint2 pixel = dispatchThreadId.xy;
    if (any(pixel >= gParams.frameDim))
        return;

    const uint idx = pixel.y * gParams.frameDim.x + pixel.x;

    SurfaceData surface = SurfaceData::createInvalid();

    ShadingData sd;
    if (loadShadingData(pixel, gParams.frameDim, gScene.camera, gVBuffer, sd))
    {
        let lod = ExplicitLodTextureSampler(0.f);
        let hints = getMaterialInstanceHints();
        let mi = gScene.materials.getMaterialInstance(sd, lod, hints);
        let bsdfProperties = mi.getProperties(sd);

        surface.posW = sd.computeRayOrigin(); // Offset to avoid self-intersection.
        surface.normalW = bsdfProperties.guideNormal;
        surface.viewW = sd.V;
        surface.diffuse = bsdfProperties.diffuseReflectionAlbedo;
        surface.specular = bsdfProperties.specularReflectance;
        surface.roughness = bsdfProperties.roughness;
        surface.viewDepth = distance(gScene.camera.getPosition(), sd.posW);
    }

    gSurfaceDataOut[idx] = surface;
}
