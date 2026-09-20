/***************************************************************************
 # ReSTIR DI - Stage 3: spatial reuse
 #
 # ============================ FILE TO IMPLEMENT ============================
 # Study notes: 1.2.2 repeating spatial reuse / 2.3.2-1 / 2.3.3 step 4
 #
 # The host dispatches this pass gParams.spatialIterations times (ping-pong).
 # Within a single dispatch you only need to combine k neighbors
 # (gParams.spatialNeighborCount).
 # ==========================================================================
 **************************************************************************/
#include "Utils/Math/MathConstants.slangh"

import Resampling;
import SurfaceData;
import Params;
import Utils.Sampling.TinyUniformSampleGenerator;
import Utils.Math.MathHelpers;
import Utils.Sampling.SampleGeneratorInterface;
import Utils.Debug.PixelDebug;

ConstantBuffer<ReSTIRDIParams> gParams;
StructuredBuffer<SurfaceData> gSurfaceData;
StructuredBuffer<Reservoir> gInputReservoirs;
RWStructuredBuffer<Reservoir> gOutputReservoirs;

// Which spatial iteration this is, used to decorrelate the RNG. Set by the host.
cbuffer PerIteration
{
    uint gIteration;
}

/** Pick one neighbor pixel offset uniformly inside a disk. (Falcor plumbing, complete) */
int2 sampleNeighborOffset<S : ISampleGenerator>(inout S sg, const float radius)
{
    float2 u = sampleNext2D(sg);
    float r = radius * sqrt(u.x);
    float theta = M_2PI * u.y;
    return int2(round(float2(r * cos(theta), r * sin(theta))));
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

    Reservoir r = gInputReservoirs[idx];

    if (surface.isValid())
    {
        TinyUniformSampleGenerator sg = TinyUniformSampleGenerator(pixel, gParams.frameCount * 16 + gIteration + 0x2000);

        /**
         * --------------------------- TODO 9 ---------------------------
         * Combine k neighboring reservoirs into the current one. (notes 1.2.1, 2.3.2-1)
         *
         * Shape of the code:
         *   BiasCorrectionData bc = BiasCorrectionData::create();
         *   // remember the accepted neighbors, you have to re-evaluate them later
         *   int2 acceptedOffsets[kMaxNeighbors]; uint acceptedCount = 0;
         *
         *   for (i = 0; i < gParams.spatialNeighborCount; ++i)
         *   {
         *       1. int2 offset = sampleNeighborOffset(sg, gParams.spatialRadius);
         *       2. int2 nPixel = int2(pixel) + offset;  skip if off-screen.
         *       3. SurfaceData nSurface = gSurfaceData[nIdx];
         *          skip unless isSurfaceSimilar(surface, nSurface,
         *          gParams.normalThreshold, gParams.depthThreshold). Mixing in
         *          neighbors with very different normals or depths creates artifacts.
         *       4. Reservoir nRes = gInputReservoirs[nIdx];
         *          float pHat = evalTargetFunction(surface, nRes.y);   // from MY point of view
         *          combineReservoir(r, nRes, pHat, sg);
         *       5. record the accepted neighbor index.
         *   }
         *
         *   // once combining is done and r.y is final, correct the bias:
         *   float pHatY = evalTargetFunction(surface, r.y);
         *   bc.add(pHatY, <current pixel's pre-combine M>, <did y come from the current pixel?>);
         *   for (each accepted neighbor j)
         *       bc.add(evalTargetFunction(nSurface_j, r.y), nRes_j.M, <did y come from j?>);
         *   r.finalizeWeight(pHatY, bc.computeMISWeight(gParams.biasCorrectionMode));
         *
         * Suggestion: start with the 1/M mode only (skip bc, use m = 1 / r.M), confirm
         * you get an image, then add 1/Z and MIS.
         *
         * Why a neighbor's sample must be re-evaluated from YOUR point of view:
         *   the neighbor has a different normal, material and position, so its target
         *   distribution p_hat differs. Mixing them as-is produces the bias described
         *   in notes 1.3.
         * --------------------------------------------------------------
         */

        // TODO 9: implement this.
    }

    gOutputReservoirs[idx] = r;
}
