/***************************************************************************
 # ReSTIR DI - the target function p_hat
 #
 # ============================ FILE TO IMPLEMENT ============================
 # p_hat is a scalar saying "how good is this sample at this pixel". It is the
 # numerator of the resampling weights and does NOT need to be normalized -- the
 # normalization constant cancels out in W. That is exactly what makes ReSTIR work.
 #
 # Study notes: 2.2.1 (target distribution without visibility)
 #              2.3.2-3 (visibility reuse)
 # ==========================================================================
 **************************************************************************/
__exported import SurfaceData;
__exported import LightSampling;
import Utils.Color.ColorHelpers;

/**
 * ------------------------------- TODO 3 -------------------------------
 * Evaluate the target function p_hat(x).
 *
 * The standard choice for ReSTIR DI:
 *
 *   p_hat(x) = luminance( f_r(x) * cos(theta) * L_e(x) )      ... without visibility
 *   p_hat(x) = luminance( f_r(x) * cos(theta) * L_e(x) ) * V  ... with visibility
 *
 * In other words, the brightness of the rendering-equation integrand. Note this is
 * the raw value -- do NOT divide by any pdf.
 *
 * How to build it:
 *   1. evalLightSample(surface.posW, ls, els) to evaluate the light sample at this
 *      shading point. Return 0 if it fails.
 *   2. evalSimpleBrdf(surface, els.dir) already returns f_r * cos.
 *   3. els.Li is the raw radiance L_e (not divided by any pdf).
 *   4. luminance() to collapse to a scalar.
 *   5. If includeVisibility, trace traceShadowRay(surface.posW, els.dir, els.distance)
 *      and return 0 when occluded.
 *
 * Why visibility is usually left out (notes 2.2.1):
 *   Tracing a shadow ray per candidate multiplies the cost by M. So candidates are
 *   evaluated without visibility, and only the one surviving sample is tested once.
 *
 * @param[in] surface Surface data at the shading point.
 * @param[in] ls Light sample to evaluate.
 * @param[in] includeVisibility Whether to trace a shadow ray.
 * @return p_hat(x) >= 0, or 0 for an invalid sample.
 * ----------------------------------------------------------------------
 */
float evalTargetFunction(const SurfaceData surface, const LightSample ls, const bool includeVisibility)
{
    if (!surface.isValid() || !ls.isValid())
        return 0.f;

    // TODO 3: implement this.
    return 0.f;
}

/** Version without visibility, which is the one used almost everywhere. */
float evalTargetFunction(const SurfaceData surface, const LightSample ls)
{
    return evalTargetFunction(surface, ls, false);
}
