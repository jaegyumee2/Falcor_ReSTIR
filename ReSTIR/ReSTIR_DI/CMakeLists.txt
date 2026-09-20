add_plugin(ReSTIRDIPass)

target_sources(ReSTIRDIPass PRIVATE
    ReSTIRDIPass.cpp
    ReSTIRDIPass.h
    Params.slang
    Reservoir.slang
    Resampling.slang
    TargetFunction.slang
    SurfaceData.slang
    LightSampling.slang
    LoadShadingData.slang
    PrepareSurfaceData.cs.slang
    InitialSampling.cs.slang
    TemporalResampling.cs.slang
    SpatialResampling.cs.slang
    FinalShading.cs.slang
)

target_copy_shaders(ReSTIRDIPass ReSTIR/ReSTIR_DI)

target_source_group(ReSTIRDIPass "ReSTIR")
