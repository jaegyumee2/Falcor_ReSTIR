/***************************************************************************
 # ReSTIR DI - study implementation (Falcor 8.0)
 **************************************************************************/
#include "ReSTIRDIPass.h"
#include "RenderGraph/RenderPassHelpers.h"
#include "RenderGraph/RenderPassStandardFlags.h"

using namespace Falcor;

namespace
{
const std::string kShaderDir = "ReSTIR/ReSTIR_DI/";
const std::string kPrepareSurfaceDataFile = kShaderDir + "PrepareSurfaceData.cs.slang";
const std::string kInitialSamplingFile = kShaderDir + "InitialSampling.cs.slang";
const std::string kTemporalResamplingFile = kShaderDir + "TemporalResampling.cs.slang";
const std::string kSpatialResamplingFile = kShaderDir + "SpatialResampling.cs.slang";
const std::string kFinalShadingFile = kShaderDir + "FinalShading.cs.slang";

const std::string kInputVBuffer = "vbuffer";
const std::string kInputMotionVectors = "mvec";

const Falcor::ChannelList kInputChannels = {
    // clang-format off
    { kInputVBuffer,       "gVBuffer",       "Visibility buffer in packed format"                       },
    { kInputMotionVectors, "gMotionVector",  "Motion vector buffer (float format)", true /* optional */ },
    // clang-format on
};

const Falcor::ChannelList kOutputChannels = {
    // clang-format off
    { "color", "gColor", "Final color",  true /* optional */, ResourceFormat::RGBA32Float },
    { "debug", "gDebug", "Debug output", true /* optional */, ResourceFormat::RGBA32Float },
    // clang-format on
};

// Scripting options.
const char* kInitialCandidateCount = "initialCandidateCount";
const char* kUseVisibilityReuse = "useVisibilityReuse";
const char* kUseTemporalResampling = "useTemporalResampling";
const char* kUseSpatialResampling = "useSpatialResampling";
const char* kMaxHistoryLength = "maxHistoryLength";
const char* kSpatialIterations = "spatialIterations";
const char* kSpatialNeighborCount = "spatialNeighborCount";
const char* kSpatialRadius = "spatialRadius";
const char* kBiasCorrectionMode = "biasCorrectionMode";
} // namespace

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, ReSTIRDIPass>();
}

ReSTIRDIPass::ReSTIRDIPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    parseProperties(props);
    mpPixelDebug = std::make_unique<PixelDebug>(mpDevice);
}

void ReSTIRDIPass::parseProperties(const Properties& props)
{
    for (const auto& [key, value] : props)
    {
        if (key == kInitialCandidateCount)
            mParams.initialCandidateCount = value;
        else if (key == kUseVisibilityReuse)
            mParams.useVisibilityReuse = (bool)value ? 1 : 0;
        else if (key == kUseTemporalResampling)
            mParams.useTemporalResampling = (bool)value ? 1 : 0;
        else if (key == kUseSpatialResampling)
            mParams.useSpatialResampling = (bool)value ? 1 : 0;
        else if (key == kMaxHistoryLength)
            mParams.maxHistoryLength = value;
        else if (key == kSpatialIterations)
            mParams.spatialIterations = value;
        else if (key == kSpatialNeighborCount)
            mParams.spatialNeighborCount = value;
        else if (key == kSpatialRadius)
            mParams.spatialRadius = value;
        else if (key == kBiasCorrectionMode)
            mParams.biasCorrectionMode = (uint32_t)(BiasCorrectionMode)value;
        else
            logWarning("Unknown property '{}' in ReSTIRDIPass properties.", key);
    }
}

Properties ReSTIRDIPass::getProperties() const
{
    Properties props;
    props[kInitialCandidateCount] = mParams.initialCandidateCount;
    props[kUseVisibilityReuse] = mParams.useVisibilityReuse != 0;
    props[kUseTemporalResampling] = mParams.useTemporalResampling != 0;
    props[kUseSpatialResampling] = mParams.useSpatialResampling != 0;
    props[kMaxHistoryLength] = mParams.maxHistoryLength;
    props[kSpatialIterations] = mParams.spatialIterations;
    props[kSpatialNeighborCount] = mParams.spatialNeighborCount;
    props[kSpatialRadius] = mParams.spatialRadius;
    props[kBiasCorrectionMode] = (BiasCorrectionMode)mParams.biasCorrectionMode;
    return props;
}

RenderPassReflection ReSTIRDIPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    addRenderPassInputs(reflector, kInputChannels);
    addRenderPassOutputs(reflector, kOutputChannels);
    return reflector;
}

void ReSTIRDIPass::compile(RenderContext* pRenderContext, const CompileData& compileData)
{
    if (any(mFrameDim != compileData.defaultTexDims))
    {
        mFrameDim = compileData.defaultTexDims;
        mResourcesDirty = true;
        mHasHistory = false;
    }
}

void ReSTIRDIPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    recreatePrograms();
    mHasHistory = false;

    if (mpScene && mpScene->hasProceduralGeometry())
        logWarning("ReSTIRDIPass: This render pass only supports triangles. Other types of geometry will be ignored.");
}

void ReSTIRDIPass::recreatePrograms()
{
    mpPrepareSurfaceDataPass = nullptr;
    mpInitialSamplingPass = nullptr;
    mpTemporalResamplingPass = nullptr;
    mpSpatialResamplingPass = nullptr;
    mpFinalShadingPass = nullptr;
    mResourcesDirty = true;
}

void ReSTIRDIPass::preparePrograms(const RenderData& renderData)
{
    FALCOR_ASSERT(mpScene);

    auto makePass = [&](const std::string& file, const DefineList& extraDefines) -> ref<ComputePass>
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(file).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines = mpScene->getSceneDefines();
        defines.add("GBUFFER_ADJUST_SHADING_NORMALS", mGBufferAdjustShadingNormals ? "1" : "0");
        defines.add(extraDefines);

        return ComputePass::create(mpDevice, desc, defines, true);
    };

    if (!mpPrepareSurfaceDataPass)
        mpPrepareSurfaceDataPass = makePass(kPrepareSurfaceDataFile, DefineList());
    if (!mpInitialSamplingPass)
        mpInitialSamplingPass = makePass(kInitialSamplingFile, DefineList());
    if (!mpTemporalResamplingPass)
        mpTemporalResamplingPass = makePass(kTemporalResamplingFile, DefineList());
    if (!mpSpatialResamplingPass)
        mpSpatialResamplingPass = makePass(kSpatialResamplingFile, DefineList());
    if (!mpFinalShadingPass)
    {
        DefineList defines;
        defines.add("USE_ENV_BACKGROUND", mpScene->useEnvBackground() ? "1" : "0");
        defines.add(getValidResourceDefines(kOutputChannels, renderData));
        mpFinalShadingPass = makePass(kFinalShadingFile, defines);
    }

    // The G-buffer setting and the connected output channels can change per frame.
    mpPrepareSurfaceDataPass->addDefine("GBUFFER_ADJUST_SHADING_NORMALS", mGBufferAdjustShadingNormals ? "1" : "0");
    mpFinalShadingPass->addDefine("GBUFFER_ADJUST_SHADING_NORMALS", mGBufferAdjustShadingNormals ? "1" : "0");
    mpFinalShadingPass->addDefine("USE_ENV_BACKGROUND", mpScene->useEnvBackground() ? "1" : "0");
    mpFinalShadingPass->getProgram()->addDefines(getValidResourceDefines(kOutputChannels, renderData));
}

void ReSTIRDIPass::prepareResources()
{
    if (!mResourcesDirty)
        return;

    const uint32_t pixelCount = mFrameDim.x * mFrameDim.y;
    FALCOR_ASSERT(pixelCount > 0);

    // Take the stride from shader reflection, so changing the Slang struct needs no C++ change.
    auto reservoirVar = mpInitialSamplingPass->getRootVar()["gOutputReservoirs"];
    auto surfaceVar = mpPrepareSurfaceDataPass->getRootVar()["gSurfaceDataOut"];

    for (uint32_t i = 0; i < 2; ++i)
    {
        mpReservoirs[i] = mpDevice->createStructuredBuffer(reservoirVar, pixelCount);
        mpReservoirs[i]->setName("ReSTIRDIPass::mpReservoirs" + std::to_string(i));
        mpSurfaceData[i] = mpDevice->createStructuredBuffer(surfaceVar, pixelCount);
        mpSurfaceData[i]->setName("ReSTIRDIPass::mpSurfaceData" + std::to_string(i));
    }
    mpPrevReservoirs = mpDevice->createStructuredBuffer(reservoirVar, pixelCount);
    mpPrevReservoirs->setName("ReSTIRDIPass::mpPrevReservoirs");

    mResourcesDirty = false;
    mHasHistory = false;
}

void ReSTIRDIPass::bindCommon(const ShaderVar& rootVar)
{
    mpScene->bindShaderData(rootVar["gScene"]);
    rootVar["gParams"].setBlob(&mParams, sizeof(mParams));
}

void ReSTIRDIPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
    {
        clearRenderPassChannels(pRenderContext, kOutputChannels, renderData);
        return;
    }

    if (is_set(mpScene->getUpdates(), IScene::UpdateFlags::RecompileNeeded) ||
        is_set(mpScene->getUpdates(), IScene::UpdateFlags::GeometryChanged))
    {
        recreatePrograms();
    }

    auto& dict = renderData.getDictionary();
    if (mOptionsChanged)
    {
        auto flags = dict.getValue(kRenderPassRefreshFlags, Falcor::RenderPassRefreshFlags::None);
        flags |= Falcor::RenderPassRefreshFlags::RenderOptionsChanged;
        dict[Falcor::kRenderPassRefreshFlags] = flags;
        mOptionsChanged = false;
    }
    mGBufferAdjustShadingNormals = dict.getValue(Falcor::kRenderPassGBufferAdjustShadingNormals, false);

    const auto& pVBuffer = renderData.getTexture(kInputVBuffer);
    const auto& pMotionVectors = renderData.getTexture(kInputMotionVectors);
    FALCOR_ASSERT(pVBuffer);

    // gScene.lightCollection is only valid in shaders once this has been built at least once.
    const auto& pLightCollection = mpScene->getLightCollection(pRenderContext);

    mParams.frameDim = mFrameDim;
    mParams.lightCount = mpScene->getLightCount();
    mParams.triangleCount = pLightCollection ? pLightCollection->getTotalLightCount() : 0;

    preparePrograms(renderData);
    prepareResources();

    mpPixelDebug->beginFrame(pRenderContext, mFrameDim);

    prepareSurfaceData(pRenderContext, pVBuffer);
    initialSampling(pRenderContext);

    if (mParams.useTemporalResampling != 0 && mHasHistory && pMotionVectors)
        temporalResampling(pRenderContext, pMotionVectors);

    if (mParams.useSpatialResampling != 0)
        spatialResampling(pRenderContext);

    finalShading(pRenderContext, pVBuffer, renderData);

    // Hand this frame's final reservoirs to the next frame as history (pointer swap, no copy).
    std::swap(mpPrevReservoirs, mpReservoirs[mCurrentReservoirIndex]);
    mHasHistory = true;

    // Ping-pong the surface buffers too: this frame's becomes next frame's "previous".
    mCurrentSurfaceIndex ^= 1;

    mpPixelDebug->endFrame(pRenderContext);

    mParams.frameCount++;
}

void ReSTIRDIPass::prepareSurfaceData(RenderContext* pRenderContext, const ref<Texture>& pVBuffer)
{
    FALCOR_PROFILE(pRenderContext, "prepareSurfaceData");

    auto rootVar = mpPrepareSurfaceDataPass->getRootVar();
    bindCommon(rootVar);
    mpPixelDebug->prepareProgram(mpPrepareSurfaceDataPass->getProgram(), rootVar);

    rootVar["gVBuffer"] = pVBuffer;
    rootVar["gSurfaceDataOut"] = mpSurfaceData[mCurrentSurfaceIndex];

    mpPrepareSurfaceDataPass->execute(pRenderContext, mFrameDim.x, mFrameDim.y);
}

void ReSTIRDIPass::initialSampling(RenderContext* pRenderContext)
{
    FALCOR_PROFILE(pRenderContext, "initialSampling");

    mCurrentReservoirIndex = 0;

    auto rootVar = mpInitialSamplingPass->getRootVar();
    bindCommon(rootVar);
    mpPixelDebug->prepareProgram(mpInitialSamplingPass->getProgram(), rootVar);

    rootVar["gSurfaceData"] = mpSurfaceData[mCurrentSurfaceIndex];
    rootVar["gOutputReservoirs"] = mpReservoirs[mCurrentReservoirIndex];

    mpInitialSamplingPass->execute(pRenderContext, mFrameDim.x, mFrameDim.y);
}

void ReSTIRDIPass::temporalResampling(RenderContext* pRenderContext, const ref<Texture>& pMotionVectors)
{
    FALCOR_PROFILE(pRenderContext, "temporalResampling");

    const uint32_t srcIndex = mCurrentReservoirIndex;
    const uint32_t dstIndex = 1 - srcIndex;

    auto rootVar = mpTemporalResamplingPass->getRootVar();
    bindCommon(rootVar);
    mpPixelDebug->prepareProgram(mpTemporalResamplingPass->getProgram(), rootVar);

    rootVar["gSurfaceData"] = mpSurfaceData[mCurrentSurfaceIndex];
    rootVar["gPrevSurfaceData"] = mpSurfaceData[1 - mCurrentSurfaceIndex];
    rootVar["gInputReservoirs"] = mpReservoirs[srcIndex];
    rootVar["gPrevReservoirs"] = mpPrevReservoirs;
    rootVar["gOutputReservoirs"] = mpReservoirs[dstIndex];
    rootVar["gMotionVectors"] = pMotionVectors;

    mpTemporalResamplingPass->execute(pRenderContext, mFrameDim.x, mFrameDim.y);

    mCurrentReservoirIndex = dstIndex;
}

void ReSTIRDIPass::spatialResampling(RenderContext* pRenderContext)
{
    FALCOR_PROFILE(pRenderContext, "spatialResampling");

    auto rootVar = mpSpatialResamplingPass->getRootVar();
    mpPixelDebug->prepareProgram(mpSpatialResamplingPass->getProgram(), rootVar);

    for (uint32_t i = 0; i < mParams.spatialIterations; ++i)
    {
        const uint32_t srcIndex = mCurrentReservoirIndex;
        const uint32_t dstIndex = 1 - srcIndex;

        bindCommon(rootVar);
        rootVar["PerIteration"]["gIteration"] = i;
        rootVar["gSurfaceData"] = mpSurfaceData[mCurrentSurfaceIndex];
        rootVar["gInputReservoirs"] = mpReservoirs[srcIndex];
        rootVar["gOutputReservoirs"] = mpReservoirs[dstIndex];

        mpSpatialResamplingPass->execute(pRenderContext, mFrameDim.x, mFrameDim.y);

        mCurrentReservoirIndex = dstIndex;
    }
}

void ReSTIRDIPass::finalShading(RenderContext* pRenderContext, const ref<Texture>& pVBuffer, const RenderData& renderData)
{
    FALCOR_PROFILE(pRenderContext, "finalShading");

    auto rootVar = mpFinalShadingPass->getRootVar();
    bindCommon(rootVar);
    mpPixelDebug->prepareProgram(mpFinalShadingPass->getProgram(), rootVar);

    rootVar["gVBuffer"] = pVBuffer;
    rootVar["gSurfaceData"] = mpSurfaceData[mCurrentSurfaceIndex];
    rootVar["gReservoirs"] = mpReservoirs[mCurrentReservoirIndex];

    for (const auto& channel : kOutputChannels)
        rootVar[channel.texname] = renderData.getTexture(channel.name);

    mpFinalShadingPass->execute(pRenderContext, mFrameDim.x, mFrameDim.y);
}

bool ReSTIRDIPass::onMouseEvent(const MouseEvent& mouseEvent)
{
    return mpPixelDebug ? mpPixelDebug->onMouseEvent(mouseEvent) : false;
}

void ReSTIRDIPass::renderUI(Gui::Widgets& widget)
{
    bool dirty = false;

    widget.text("ReSTIR DI (2020, Bitterli et al.)");
    widget.tooltip(
        "Turn the stages on one at a time and compare how the noise drops.\n"
        "Initial only -> +Visibility reuse -> +Temporal -> +Spatial"
    );

    if (auto group = widget.group("1. Initial sampling", true))
    {
        dirty |= group.var("Candidates M", mParams.initialCandidateCount, 1u, 1024u);
        group.tooltip("Number of light candidates generated per pixel. Notes 2.2, streaming RIS.");

        bool useVisibilityReuse = mParams.useVisibilityReuse != 0;
        if (group.checkbox("Visibility reuse", useVisibilityReuse))
        {
            mParams.useVisibilityReuse = useVisibilityReuse ? 1 : 0;
            dirty = true;
        }
        group.tooltip("Discard the reservoir if the selected sample is occluded. Notes 2.3.2-3.");
    }

    if (auto group = widget.group("2. Temporal reuse", true))
    {
        bool useTemporal = mParams.useTemporalResampling != 0;
        if (group.checkbox("Enabled", useTemporal))
        {
            mParams.useTemporalResampling = useTemporal ? 1 : 0;
            dirty = true;
        }
        dirty |= group.var("Max history (M clamp)", mParams.maxHistoryLength, 1u, 100u);
        group.tooltip("Clamp M_prev <= maxHistory * M_new. Notes 1.2.3-2, clamping.");
    }

    if (auto group = widget.group("3. Spatial reuse", true))
    {
        bool useSpatial = mParams.useSpatialResampling != 0;
        if (group.checkbox("Enabled", useSpatial))
        {
            mParams.useSpatialResampling = useSpatial ? 1 : 0;
            dirty = true;
        }
        dirty |= group.var("Iterations n", mParams.spatialIterations, 0u, 8u);
        dirty |= group.var("Neighbors k", mParams.spatialNeighborCount, 1u, 32u);
        dirty |= group.var("Radius (px)", mParams.spatialRadius, 1.f, 200.f);
        group.tooltip("The effective candidate count grows roughly like k^n * M. Notes 1.2.2.");
    }

    if (auto group = widget.group("4. Bias correction", true))
    {
        BiasCorrectionMode mode = (BiasCorrectionMode)mParams.biasCorrectionMode;
        if (group.dropdown("m(y) mode", mode))
        {
            mParams.biasCorrectionMode = (uint32_t)mode;
            dirty = true;
        }
        group.tooltip("1/M darkens boundaries, 1/Z is noisy, MIS balance fixes both. Notes 1.3 / section 3.");
    }

    if (auto group = widget.group("Shading & debug", true))
    {
        bool useFinalVisibility = mParams.useFinalVisibility != 0;
        if (group.checkbox("Final visibility ray", useFinalVisibility))
        {
            mParams.useFinalVisibility = useFinalVisibility ? 1 : 0;
            dirty = true;
        }

        DebugOutput debugOutput = (DebugOutput)mParams.debugOutput;
        if (group.dropdown("Debug output", debugOutput))
        {
            mParams.debugOutput = (uint32_t)debugOutput;
            dirty = true;
        }
        group.tooltip("Goes out on the 'debug' output channel. Hook it up in the render graph.");
    }

    if (auto group = widget.group("Pixel debug"))
        mpPixelDebug->renderUI(group);

    if (dirty)
    {
        mOptionsChanged = true;
        mHasHistory = false; // Drop the history whenever a setting changes.
    }
}
