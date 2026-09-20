/***************************************************************************
 # ReSTIR DI - reconstruct ShadingData from the VBuffer (Falcor plumbing, complete)
 **************************************************************************/
__exported import Scene.Scene;
__exported import Scene.Shading;
__exported import Scene.HitInfo;
import Scene.Material.ShadingUtils;

uint getMaterialInstanceHints()
{
    uint hints = 0;
#if GBUFFER_ADJUST_SHADING_NORMALS
    hints |= (uint)MaterialInstanceHints::AdjustShadingNormal;
#endif
    return hints;
}

/**
 * Reconstruct ShadingData from a pixel's VBuffer entry.
 * @return True unless this is a background pixel. sd.V is always valid.
 */
bool loadShadingData(const uint2 pixel, const uint2 frameDim, const Camera camera, Texture2D<PackedHitInfo> vbuffer, out ShadingData sd)
{
    sd = {};

    const float3 rayDir = camera.computeRayPinhole(pixel, frameDim).dir;
    bool valid = false;

    const HitInfo hit = HitInfo(vbuffer[pixel]);
    if (hit.isValid() && hit.getType() == HitType::Triangle)
    {
        const TriangleHit triangleHit = hit.getTriangleHit();
        const VertexData v = gScene.getVertexData(triangleHit);
        const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
        sd = gScene.materials.prepareShadingData(v, materialID, -rayDir);
        valid = true;
    }

    sd.V = -rayDir;
    return valid;
}
