/***************************************************************************
 # ReSTIR DI - combining reservoirs and correcting the bias
 #
 # ============================ FILE TO IMPLEMENT ============================
 # Study notes: 1.2.1 combining reservoirs / 1.2.3 what r.M is for /
 #              1.3 removing bias with MIS / section 3
 # ==========================================================================
 **************************************************************************/
__exported import Reservoir;
__exported import TargetFunction;
__exported import Params;
import Utils.Sampling.SampleGeneratorInterface;

/**
 * ------------------------------- TODO 4 -------------------------------
 * Combine reservoir rIn into reservoir r. (notes 1.2.1)
 *
 * The idea: treat the whole of rIn as ONE candidate with one weight and stream it
 * into r. WRS guarantees that this is mathematically the same as concatenating the
 * two input streams.
 *
 * The weight to use is (notes 1.2.3, 3.1):
 *
 *   w = p_hat_dest(rIn.y) * rIn.W * rIn.M
 *
 *   - p_hat_dest(rIn.y) : rIn's sample evaluated from the RECEIVING pixel's point of
 *                         view. The neighbor has a different target distribution, so
 *                         you must re-evaluate it at your own shading point.
 *   - rIn.W             : the estimate of 1/p(rIn.y).
 *   - rIn.M             : how many candidates rIn stands for, i.e. its confidence.
 *
 * How to build it:
 *   1. Save r.M before combining.
 *   2. Call r.update(rIn.y, w, sg).
 *   3. update() only bumps M by one, so afterwards you must overwrite
 *      r.M = (saved M) + rIn.M. Forget this and the effective candidate count
 *      never accumulates.
 *
 * @param[in,out] r The destination, i.e. the current pixel's reservoir.
 * @param[in] rIn The reservoir being merged in (a neighbor, or the previous frame).
 * @param[in] targetPdfAtDest p_hat(rIn.y) evaluated at the current pixel.
 * @return True if rIn's sample was selected.
 * ----------------------------------------------------------------------
 */
bool combineReservoir<S : ISampleGenerator>(
    inout Reservoir r,
    const Reservoir rIn,
    const float targetPdfAtDest,
    inout S sg
)
{
    // TODO 4: implement this.
    return false;
}

/**
 * Accumulator for the statistics needed by the correction weight m(y).
 *
 * For every source i that took part in the combination (the current pixel plus its
 * neighbors), it collects p_hat_i(y) -- the final selected sample y evaluated from
 * source i's point of view -- together with that source's M_i.
 *
 * Usage:
 *   BiasCorrectionData bc = BiasCorrectionData::create();
 *   // for every source that took part:
 *   bc.add(targetPdfOfYAtSource_i, M_i, isTheSourceThatProvidedY);
 *   float m = bc.computeMISWeight(mode);
 */
struct BiasCorrectionData
{
    float pdfSum;      ///< sum_i p_hat_i(y) * M_i, over all sources.
    float selectedPdf; ///< p_hat_z(y) * M_z for the source z that provided y.
    uint validM;       ///< Z: sum of M_i over the sources with p_hat_i(y) != 0.
    uint totalM;       ///< Sum of M_i over all sources.

    static BiasCorrectionData create()
    {
        BiasCorrectionData bc = {};
        return bc;
    }

    [mutating]
    void add(const float targetPdfOfY, const uint M, const bool isSelectedSource)
    {
        totalM += M;
        if (targetPdfOfY > 0.f)
        {
            pdfSum += targetPdfOfY * M;
            validM += M;
        }
        if (isSelectedSource)
            selectedPdf = targetPdfOfY * M;
    }

    /**
     * ------------------------------- TODO 5 -------------------------------
     * Compute the correction weight m(y). (notes 1.3.2, section 3)
     *
     * Depending on mode:
     *
     *   BiasCorrectionMode::Naive_1overM
     *       m(y) = 1 / totalM
     *       Simplest. Ignores that p_hat differs per neighbor, so boundaries darken.
     *
     *   BiasCorrectionMode::Naive_1overZ
     *       m(y) = 1 / validM
     *       Only counts the sources that COULD have produced y. Unbiased, but the
     *       weight spikes when validM gets small, so it is noisy.
     *
     *   BiasCorrectionMode::MIS_Balance
     *       m(y) = selectedPdf / pdfSum
     *       Balance heuristic. Unbiased and keeps the noise down.
     *
     * Watch out: return 0 when the denominator is zero.
     * ----------------------------------------------------------------------
     */
    float computeMISWeight(const uint mode)
    {
        // TODO 5: implement this.
        return 0.f;
    }
};
