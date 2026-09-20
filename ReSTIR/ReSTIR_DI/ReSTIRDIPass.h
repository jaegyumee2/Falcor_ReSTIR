/***************************************************************************
 # ReSTIR DI - study implementation (Falcor 8.0)
 #
 # 2020, Bitterli et al.
 # "Spatiotemporal reservoir resampling for real-time ray tracing with
 #  dynamic direct lighting"
 **************************************************************************/
#pragma once

#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "Utils/Debug/PixelDebug.h"
#include "Params.slang"

using namespace Falcor;

/**
 * A render pass for implementing ReSTIR DI from scratch.
 *
 * Pipeline (notes 2.3.3, the full algorithm):
 *   0. PrepareSurfaceData : VBuffer -> compact surface buffer (ping-ponged for temporal)
 *   1. InitialSampling    : M candidates per pixel + streaming RIS + visibility reuse
 *   2. TemporalResampling : reproject and combine with last frame's reservoir (M clamping)
 *   3. SpatialResampling  : combine k neighbors, repeated n times
 *   4. FinalShading       : shade with the final sample
 *
 * Every stage can be toggled independently in the UI, so turn them on one at a
 * time and watch how the noise drops.
 */
class ReSTIRDIPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(ReSTIRDIPass, "ReSTIRDIPass", {"ReSTIR direct illumination (study implementation)."})

    static ref<ReSTIRDIPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<ReSTIRDIPass>(pDevice, props);
    }

    ReSTIRDIPass(ref<Device> pDevice, const Properties& props);

    virtual Properties getProperties() const override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override;

private:
    void parseProperties(const Properties& props);
    void recreatePrograms();
    void preparePrograms(const RenderData& renderData);
    void prepareResources();

    void prepareSurfaceData(RenderContext* pRenderContext, const ref<Texture>& pVBuffer);
    void initialSampling(RenderContext* pRenderContext);
    void temporalResampling(RenderContext* pRenderContext, const ref<Texture>& pMotionVectors);
    void spatialResampling(RenderContext* pRenderContext);
    void finalShading(RenderContext* pRenderContext, const ref<Texture>& pVBuffer, const RenderData& renderData);

    /** Bind the shared parameters and resources. */
    void bindCommon(const ShaderVar& rootVar);

    ref<Scene> mpScene;
    std::unique_ptr<PixelDebug> mpPixelDebug;

    ReSTIRDIParams mParams;

    ref<ComputePass> mpPrepareSurfaceDataPass;
    ref<ComputePass> mpInitialSamplingPass;
    ref<ComputePass> mpTemporalResamplingPass;
    ref<ComputePass> mpSpatialResamplingPass;
    ref<ComputePass> mpFinalShadingPass;

    /// Ping-pong reservoir buffers for this frame's resampling chain.
    ref<Buffer> mpReservoirs[2];
    /// Last frame's final reservoirs, the input to temporal reuse.
    ref<Buffer> mpPrevReservoirs;
    /// Current and previous frame surface data.
    ref<Buffer> mpSurfaceData[2];

    /// Index into mpReservoirs holding this frame's result.
    uint32_t mCurrentReservoirIndex = 0;
    /// Index into mpSurfaceData for the current frame.
    uint32_t mCurrentSurfaceIndex = 0;

    uint2 mFrameDim = {0, 0};
    bool mOptionsChanged = false;
    bool mGBufferAdjustShadingNormals = false;
    bool mResourcesDirty = true;
    /// No temporal history on the first frame or right after a reset.
    bool mHasHistory = false;
};
