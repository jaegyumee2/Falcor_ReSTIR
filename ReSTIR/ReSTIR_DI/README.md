# ReSTIR_DI -- implementation guide

A study render pass for implementing ReSTIR DI (Bitterli et al. 2020) yourself.
All the Falcor plumbing (buffers, dispatch, light sampling, shading, UI) is done.
**Only the ReSTIR algorithm itself is left as TODOs.**

Matching study notes: `MediaStudy/ReSTIR/2020_ReSTIR_DI/ReSTIR_Direct Illumination.md`

---

## Files

| File | Role | Status |
|---|---|---|
| `Params.slang` | Host/device shared parameters and enums | done |
| `LightSampling.slang` | Generate light samples, re-evaluate them anywhere, shadow rays | done |
| `SurfaceData.slang` | Compact surface buffer, simple BRDF, neighbor similarity test | done |
| `LoadShadingData.slang` | VBuffer -> ShadingData | done |
| `PrepareSurfaceData.cs.slang` | Stage 0 | done |
| **`Reservoir.slang`** | Reservoir struct, WRS update, finalizing W | **TODO 1, 2** |
| **`TargetFunction.slang`** | The target function p_hat | **TODO 3** |
| **`Resampling.slang`** | Combining reservoirs, bias correction m(y) | **TODO 4, 5** |
| **`InitialSampling.cs.slang`** | Stage 1: streaming RIS + visibility reuse | **TODO 6, 7** |
| **`TemporalResampling.cs.slang`** | Stage 2: temporal reuse | **TODO 8** |
| **`SpatialResampling.cs.slang`** | Stage 3: spatial reuse | **TODO 9** |
| `FinalShading.cs.slang` | Stage 4: final shading, debug views | done |
| `ReSTIRDIPass.cpp/.h` | Render pass, buffer ping-pong, UI | done |

---

## Suggested order

Do one step at a time and look at the image after each. Building as-is gives a
**black screen**, which is correct: every reservoir is empty.

### Step 1 -- get plain RIS running (TODO 1, 2, 3, 6)

- `Reservoir::update()` -- the WRS replacement probability `w / wSum`
- `Reservoir::finalizeWeight()` -- `W = m(y) * wSum / p_hat(y)`
- `evalTargetFunction()` -- `p_hat = luminance(f_r * cos * L_e)`
- the M-loop in `InitialSampling`

Turn temporal and spatial off in the UI and run.
- You should get a **noisy but recognizable 1spp image** with the lights visible.
- Raising M from 1 -> 8 -> 32 should visibly cut the noise.

Check: enable `AccumulatePass`, let it converge, and compare against
`MinimalPathTracer` (direct only). The brightness must match. If it is too dark or
too bright, the `1/M` in `W` or the `p_hat` normalization is wrong.

### Step 2 -- visibility reuse (TODO 7)

- One shadow ray for the selected sample, discard the reservoir if occluded.

You should get shadows, and less noise along shadow boundaries.

### Step 3 -- temporal reuse (TODO 4, 8)

- `combineReservoir()` -- weight `p_hat_dest(rIn.y) * rIn.W * rIn.M`
- M clamping and combination in the temporal stage; start with `m = 1/r.M` fixed.

- Hold the camera still and the noise should collapse within a few frames.
- Set Debug output to `Reservoir M` and watch M accumulate and brighten.
- Drop "Max history" to 1 and confirm the noise comes back (notes 1.2.3-2).

Common bug: if `combineReservoir()` does not overwrite `r.M` with `+ rIn.M`, M never
accumulates and temporal reuse does almost nothing.

### Step 4 -- spatial reuse (TODO 9)

- Combine k neighbors, filtered by the similarity test.

- Move the camera (which breaks temporal) and the noise should still hold up.
- Raising "Iterations n" to 2 should smooth it further.
- Deliberately disable the similarity test and you will see light leaking across
  object boundaries.

### Step 5 -- remove the bias (TODO 5)

- Implement all three modes of `computeMISWeight()` and use `BiasCorrectionData`
  in the temporal and spatial stages.

Enable `AccumulatePass`, converge fully, then compare the three modes:
- `1/M`: boundaries and corners are subtly **darker**
- `1/Z`: brightness is right but it is **noisy**
- `MIS balance`: fixes both

Putting those three images side by side is the whole point of notes 1.3 and section 3.

---

## Running

```
build/windows-vs2022/bin/Release/Mogwai.exe --script=ReSTIR/script/ReSTIRDI.py
```

Load a scene (File -> Load Scene, e.g. `media/Arcade/Arcade.pyscene`) and toggle the
stages in the ReSTIRDIPass UI.

### Debugging tools

- **Debug output dropdown** -- select the `debug` output channel in Mogwai to view it.
  `Reservoir M`, `Selected light index` and `Temporal reuse mask` are the useful ones.
  (Selected light index: neighboring pixels bleeding into the same color means reuse
  is working.)
- **Pixel debug** -- put `print("wSum", r.wSum);` in a shader, enable Pixel debug in the
  UI, and click a pixel to print its values.

---

## Reference implementation

If you get stuck: `Source/Falcor/Rendering/RTXDI/` (the NVIDIA RTXDI wrapper).
The structure is quite different, so try it yourself first.

---

## Known simplifications

This is written for learning, so the following are simplified. Extend as needed.

- Light selection is **uniform**. Scenes with very many lights want power- or
  BVH-based selection.
- Delta lights (point, directional) and area lights are mixed into one RIS stream.
  Strictly the measures differ, but production implementations usually do this too.
- The target function p_hat uses a simple diffuse + GGX BRDF. Final shading uses the
  real material.
- Texture LOD is always 0.
