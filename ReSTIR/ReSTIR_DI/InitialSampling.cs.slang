/***************************************************************************
 # ReSTIR DI - Stage 1: initial candidate generation (streaming RIS) + visibility reuse
 #
 # ============================ FILE TO IMPLEMENT ============================
 # Study notes: 2.2 Streaming RIS / 2.3.2-3 Visibility Reuse /
 #              2.3.3 full algorithm, steps 1-2
 # ==========================================================================
 **************************************************************************/
import Resampling;
import SurfaceData;
import Params;
import Utils.Sampling.TinyUniformSampleGenerator;
import Utils.Debug.PixelDebug;

ConstantBuffer<ReSTIRDIParams> gParams;
StructuredBuffer<SurfaceData> gSurfaceData;
RWStructuredBuffer<Reservoir> gOutputReservoirs;

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const uint2 pixel = dispatchThreadId.xy;
    if (any(pixel >= gParams.frameDim))
        return;

    printSetPixel(pixel);

    const uint idx = pixel.y * gParams.frameDim.x + pixel.x;
    const SurfaceData surface = gSurfaceData[idx];

    Reservoir r = Reservoir::createEmpty();

    if (surface.isValid() && getTotalLightCount() > 0)
    {
        TinyUniformSampleGenerator sg = TinyUniformSampleGenerator(pixel, gParams.frameCount);

        /**
         * --------------------------- TODO 6 ---------------------------
         * Streaming RIS: generate M candidates and compress them into one
         * reservoir. (notes 2.2.1)
         *
         * for (i = 0; i < gParams.initialCandidateCount; ++i)
         * {
         *     1. LightSample x = generateLightSample(sg);
         *     2. float sourcePdf = getLightSelectionPdf() * (solid-angle pdf of x);
         *        - the solid-angle pdf comes from els.pdf in evalLightSample().
         *        - if evaluation fails (back-facing light etc.) stream this candidate
         *          with w = 0. M must STILL be incremented.
         *     3. float pHat = evalTargetFunction(surface, x);   // without visibility
         *     4. float w = (sourcePdf > 0) ? pHat / sourcePdf : 0;
         *     5. r.update(x, w, sg);
         * }
         *
         * After the loop, finalize W. This is a single distribution, so m(y) = 1/M:
         *     float pHatY = evalTargetFunction(surface, r.y);
         *     r.finalizeWeight(pHatY, 1.0 / r.M);
         *
         * Hint: evalTargetFunction() calls evalLightSample() internally, so there is
         * some duplicated work. Get it working first, then optionally refactor to
         * compute els once and reuse it.
         * --------------------------------------------------------------
         */

        // TODO 6: implement this.

        /**
         * --------------------------- TODO 7 ---------------------------
         * Visibility reuse. (notes 2.3.2-3)
         *
         * If gParams.useVisibilityReuse is 1 and r is valid, trace one shadow ray for
         * the selected sample y. If it is occluded, discard the reservoir: set
         * r.W = 0 (or wSum = 0).
         *
         * Why: it stops a bad, occluded sample from spreading to neighboring pixels
         * through spatiotemporal reuse. The cost is one ray per pixel, not M, because
         * only the single surviving sample is tested.
         *
         * Hint: EvaluatedLightSample els; evalLightSample(surface.posW, r.y, els);
         *       traceShadowRay(surface.posW, els.dir, els.distance)
         * --------------------------------------------------------------
         */

        // TODO 7: implement this.
    }

    gOutputReservoirs[idx] = r;
}
