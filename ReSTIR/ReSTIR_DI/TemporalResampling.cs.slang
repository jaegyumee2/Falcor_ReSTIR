/***************************************************************************
 # ReSTIR DI - Stage 2: temporal reuse
 #
 # ============================ FILE TO IMPLEMENT ============================
 # Study notes: 1.2.2 accumulation through temporal reuse / 1.2.3-2 clamping /
 #              2.3.3 step 3
 #
 # Reprojection and the validity test are Falcor plumbing, already written.
 # You fill in the reservoir combination, the M clamping and finalizing W.
 # ==========================================================================
 **************************************************************************/
import Resampling;
import SurfaceData;
import Params;
import Utils.Sampling.TinyUniformSampleGenerator;
import Utils.Debug.PixelDebug;

ConstantBuffer<ReSTIRDIParams> gParams;
StructuredBuffer<SurfaceData> gSurfaceData;     ///< Current frame surfaces.
StructuredBuffer<SurfaceData> gPrevSurfaceData; ///< Previous frame surfaces.
StructuredBuffer<Reservoir> gInputReservoirs;   ///< This frame's initial reservoirs.
StructuredBuffer<Reservoir> gPrevReservoirs;    ///< Last frame's final reservoirs.
RWStructuredBuffer<Reservoir> gOutputReservoirs;
Texture2D<float2> gMotionVectors;

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const uint2 pixel = dispatchThreadId.xy;
    if (any(pixel >= gParams.frameDim))
        return;

    printSetPixel(pixel);

    const uint idx = pixel.y * gParams.frameDim.x + pixel.x;
    const SurfaceData surface = gSurfaceData[idx];

    Reservoir r = gInputReservoirs[idx];

    if (surface.isValid())
    {
        TinyUniformSampleGenerator sg = TinyUniformSampleGenerator(pixel, gParams.frameCount + 0x1000);

        // --- Reprojection (Falcor plumbing, complete) -------------------------
        // Falcor motion vectors are (prevUV - currUV) in normalized screen space.
        const float2 currUV = (float2(pixel) + 0.5f) / float2(gParams.frameDim);
        const float2 prevUV = currUV + gMotionVectors[pixel];
        const int2 prevPixel = int2(floor(prevUV * float2(gParams.frameDim)));

        bool prevValid = all(prevPixel >= 0) && all(prevPixel < int2(gParams.frameDim));
        uint prevIdx = 0;
        SurfaceData prevSurface = SurfaceData::createInvalid();
        if (prevValid)
        {
            prevIdx = uint(prevPixel.y) * gParams.frameDim.x + uint(prevPixel.x);
            prevSurface = gPrevSurfaceData[prevIdx];
            // Reject geometrically dissimilar surfaces (disocclusion and friends).
            prevValid = isSurfaceSimilar(surface, prevSurface, gParams.normalThreshold, gParams.depthThreshold);
        }
        // ----------------------------------------------------------------------

        if (prevValid)
        {
            Reservoir prevReservoir = gPrevReservoirs[prevIdx];

            /**
             * ------------------------- TODO 8 -------------------------
             * Combine the previous frame's reservoir into the current one.
             *
             * 1) M clamping (notes 1.2.3-2)
             *    Left unbounded, the history grows until a new sample has
             *    essentially zero chance of being picked.
             *    prevReservoir.M = min(prevReservoir.M, gParams.maxHistoryLength * r.M);
             *    (r.M here is this frame's initial candidate count M)
             *
             * 2) Collect the bias correction statistics
             *    BiasCorrectionData bc = BiasCorrectionData::create();
             *    Two sources take part: the current pixel (r) and the reprojected
             *    pixel (prevReservoir). The selected y is only known AFTER combining,
             *    so the order is:
             *      a. Remember the pre-combine state (currM = r.M, prevM = prevReservoir.M)
             *         and compute the weight input
             *         p_hat_curr(prevReservoir.y) = evalTargetFunction(surface, prevReservoir.y).
             *      b. combineReservoir(r, prevReservoir, p_hat_curr(prevReservoir.y), sg).
             *      c. With the now-final r.y, compute
             *           p_hat_curr(r.y) = evalTargetFunction(surface, r.y)
             *           p_hat_prev(r.y) = evalTargetFunction(prevSurface, r.y)
             *         and call bc.add(...) twice. Use the return value of (b) to know
             *         which source provided r.y (isSelectedSource).
             *
             * 3) Finalize W
             *    float m = bc.computeMISWeight(gParams.biasCorrectionMode);
             *    r.finalizeWeight(p_hat_curr(r.y), m);
             *
             * 4) Debug flag
             *    r.flags |= Reservoir::kFlagTemporalReuse;
             *
             * Suggestion: get the 1/M mode working first (skip bc entirely, use
             * m = 1/r.M), confirm you get an image, then add 1/Z and MIS.
             * ----------------------------------------------------------
             */

            // TODO 8: implement this.
        }
    }

    gOutputReservoirs[idx] = r;
}
