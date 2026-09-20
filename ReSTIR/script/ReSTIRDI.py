from falcor import *

def render_graph_ReSTIRDI():
    g = RenderGraph("ReSTIRDI")

    VBufferRT = createPass("VBufferRT", {'useAlphaTest': True})
    g.addPass(VBufferRT, "VBufferRT")

    ReSTIRDIPass = createPass("ReSTIRDIPass")
    g.addPass(ReSTIRDIPass, "ReSTIRDIPass")

    # Enable this to converge to a reference image.
    # Keep it disabled to look at the raw 1spp ReSTIR output.
    AccumulatePass = createPass("AccumulatePass", {'enabled': False, 'precisionMode': 'Single'})
    g.addPass(AccumulatePass, "AccumulatePass")

    ToneMapper = createPass("ToneMapper", {'autoExposure': False, 'exposureCompensation': 0.0})
    g.addPass(ToneMapper, "ToneMapper")

    g.addEdge("VBufferRT.vbuffer", "ReSTIRDIPass.vbuffer")
    g.addEdge("VBufferRT.mvec", "ReSTIRDIPass.mvec")
    g.addEdge("ReSTIRDIPass.color", "AccumulatePass.input")
    g.addEdge("AccumulatePass.output", "ToneMapper.src")

    g.markOutput("ToneMapper.dst")
    # Use together with the "Debug output" dropdown in the pass UI.
    g.markOutput("ReSTIRDIPass.debug")
    return g

ReSTIRDI = render_graph_ReSTIRDI()
try: m.addGraph(ReSTIRDI)
except NameError: None
