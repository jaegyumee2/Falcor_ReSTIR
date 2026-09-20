/***************************************************************************
 # ReSTIR DI - parameters shared between host and device
 #
 # Reference: Bitterli et al. 2020, "Spatiotemporal reservoir resampling for
 # real-time ray tracing with dynamic direct lighting"
 **************************************************************************/
#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

/**
 * How to compute the correction weight m(y) when combining reservoirs.
 * (study notes 1.3 / section 3)
 *
 * Final weight:  W = (1 / p_hat(y)) * [ m(y) * sum_i w_i ]
 *
 * The choice of m(y) decides how much bias and how much noise you get.
 */
enum class BiasCorrectionMode : uint32_t
{
    /// m(y) = 1/M. Simplest, but ignores that p_hat differs between neighbors,
    /// so it darkens geometric boundaries.
    Naive_1overM = 0,
    /// m(y) = 1/Z, where Z sums M over the sources with p_hat_i(y) != 0.
    /// Unbiased, but the weight spikes when Z gets small, so it is noisy. (notes 1.3.2-1)
    Naive_1overZ = 1,
    /// m(y) = p_hat_z(y)*M_z / sum_i p_hat_i(y)*M_i. Balance heuristic.
    /// Unbiased and keeps the noise down. (notes 1.3.2-2)
    MIS_Balance = 2,
};

FALCOR_ENUM_INFO(
    BiasCorrectionMode,
    {
        {BiasCorrectionMode::Naive_1overM, "1/M (biased)"},
        {BiasCorrectionMode::Naive_1overZ, "1/Z (unbiased, noisy)"},
        {BiasCorrectionMode::MIS_Balance, "MIS balance (unbiased)"},
    }
);
FALCOR_ENUM_REGISTER(BiasCorrectionMode);

/** Debug views. These go out on the 'debug' output channel. */
enum class DebugOutput : uint32_t
{
    Disabled = 0,
    /// r.M, the effective candidate count. Shows at a glance whether reuse is working.
    ReservoirM = 1,
    /// r.W, the unbiased contribution weight.
    ReservoirW = 2,
    /// p_hat(y) of the final sample.
    TargetFunction = 3,
    /// Selected light index as a color. Neighboring pixels bleeding into the same
    /// color means reuse is happening.
    SelectedLightIndex = 4,
    /// Pixels where temporal reprojection succeeded.
    TemporalReuseMask = 5,
};

FALCOR_ENUM_INFO(
    DebugOutput,
    {
        {DebugOutput::Disabled, "Disabled"},
        {DebugOutput::ReservoirM, "Reservoir M"},
        {DebugOutput::ReservoirW, "Reservoir W"},
        {DebugOutput::TargetFunction, "Target function p_hat"},
        {DebugOutput::SelectedLightIndex, "Selected light index"},
        {DebugOutput::TemporalReuseMask, "Temporal reuse mask"},
    }
);
FALCOR_ENUM_REGISTER(DebugOutput);

/**
 * Parameter block shared between host and device.
 * Follow HLSL packing rules (16-byte rows). No bools: 1 byte on the host,
 * 4 bytes in HLSL.
 */
struct ReSTIRDIParams
{
    uint2 frameDim = {0, 0}; ///< Screen resolution.
    uint frameCount = 0;     ///< Frame index, used to seed the RNG.
    uint lightCount = 0;     ///< Number of analytic lights.

    uint triangleCount = 0; ///< Number of emissive triangles.
    /// M: number of initial light candidates per pixel. (notes 2.2)
    uint initialCandidateCount = 32;
    /// Trace one shadow ray for the selected initial sample and drop the reservoir
    /// if it is occluded. (notes 2.3.2-3)
    uint useVisibilityReuse = 1;
    uint useTemporalResampling = 1;

    uint useSpatialResampling = 1;
    /// Clamp M_prev <= maxHistoryLength * M_new when combining temporally. (notes 1.2.3-2)
    uint maxHistoryLength = 20;
    /// n: number of spatial reuse iterations. Effective candidate count grows like k^n * M.
    uint spatialIterations = 1;
    uint spatialNeighborCount = 5; ///< k: neighbors combined per iteration.

    float spatialRadius = 30.f;   ///< Radius in pixels of the disk we pick neighbors from.
    /// Accept a neighbor / history pixel only if dot(n, n_neighbor) > normalThreshold.
    float normalThreshold = 0.9f;
    /// Accept a neighbor / history pixel only if the relative depth difference is below this.
    float depthThreshold = 0.1f;
    uint biasCorrectionMode = (uint)BiasCorrectionMode::Naive_1overM;

    uint debugOutput = (uint)DebugOutput::Disabled;
    uint useFinalVisibility = 1; ///< Trace a shadow ray during final shading.
    uint _pad0 = 0;
    uint _pad1 = 0;
};

END_NAMESPACE_FALCOR
