/***************************************************************************
 # ReSTIR DI - the reservoir and weighted reservoir sampling
 #
 # ============================ FILE TO IMPLEMENT ============================
 # This is the heart of ReSTIR. Fill in the TODOs yourself.
 # Study notes: MediaStudy/ReSTIR/2020_ReSTIR_DI/ReSTIR_Direct Illumination.md
 #   - 1.1 Weighted Reservoir Sampling
 #   - 1.2.1 combining reservoirs
 #   - 1.2.3 what r.M is for
 # ==========================================================================
 **************************************************************************/
__exported import LightSampling;
import Utils.Sampling.SampleGeneratorInterface;

/**
 * A reservoir. One per pixel. It summarizes every candidate streamed through it
 * into a single sample y plus a few scalars, so memory is O(1) instead of O(M).
 * (notes 2.2.2)
 *
 * 32 bytes. The host derives the stride from shader reflection, so you can change
 * these fields without touching any C++.
 */
struct Reservoir
{
    LightSample y; ///< Currently selected sample. (16B)
    float wSum;    ///< Sum of the weights of every candidate seen so far, sum_i w_i.
    float W;       ///< Unbiased contribution weight. Stands in for 1/p(y). (notes 3.1)
    uint M;        ///< Number of candidates processed so far. This is the confidence. (notes 1.2.3)
    uint flags;    ///< Debug flags only, no effect on the algorithm. bit0 = temporal reprojection succeeded.

    static Reservoir createEmpty()
    {
        Reservoir r = {};
        r.y = LightSample::createInvalid();
        r.wSum = 0.f;
        r.W = 0.f;
        r.M = 0;
        r.flags = 0;
        return r;
    }

    static const uint kFlagTemporalReuse = 0x1;

    bool isValid() { return y.isValid() && W > 0.f; }

    /**
     * ------------------------------- TODO 1 -------------------------------
     * The streaming update of weighted reservoir sampling. (notes 1.1.1)
     *
     * When a new candidate x arrives with weight w:
     *   1. Accumulate w into wSum.
     *   2. Increment M.
     *   3. Replace the current selection y with x with probability w / wSum.
     *      This is the probability that keeps the invariant proved in notes 1.1.2.
     *
     * Watch out for:
     *   - If w <= 0 nothing gets selected, but you must STILL increment M.
     *     Skipping it throws off the normalization in W later.
     *   - Do not divide when wSum is zero.
     *
     * @param[in] x New candidate sample.
     * @param[in] w Its weight. For initial candidate generation this is
     *              p_hat(x)/p(x); when combining reservoirs it is
     *              p_hat(r.y) * r.W * r.M.
     * @return True if y was replaced by x.
     * ----------------------------------------------------------------------
     */
    [mutating]
    bool update<S : ISampleGenerator>(const LightSample x, const float w, inout S sg)
    {
        // TODO 1: implement this.
        return false;
    }

    /**
     * ------------------------------- TODO 2 -------------------------------
     * Finalize the weight W. (notes 1.2.3 aside, 1.3.1)
     *
     *   W = (1 / p_hat(y)) * [ m(y) * sum_i w_i ]
     *
     * m(y) is the correction weight:
     *   - initial candidate generation (single distribution): m(y) = 1/M
     *   - combining reservoirs (multiple distributions): 1/M, 1/Z or MIS balance
     * The caller computes m(y) and passes it in.
     *
     * Watch out: if p_hat(y) is zero, set W = 0 rather than dividing.
     *
     * @param[in] targetPdf p_hat(y) for the selected sample y.
     * @param[in] m The correction weight m(y).
     * ----------------------------------------------------------------------
     */
    [mutating]
    void finalizeWeight(const float targetPdf, const float m)
    {
        // TODO 2: implement this.
        W = 0.f;
    }
};
