# ReSTIR workspace

Everything written by hand for `Falcor_ReSTIR` lives here. The stock Falcor tree
(`Source/`) is left untouched, so pulling upstream updates will not conflict.

```
ReSTIR/
|-- CMakeLists.txt     pulled in by add_subdirectory(ReSTIR) in the root CMakeLists.txt
|-- ReSTIR_DI/         the ReSTIR DI render pass (implementation guide in its own README.md)
|-- script/            render graph scripts and experiment runners (Python)
|-- notes/             working notes
`-- results/           renders and comparison images
```

## Adding another pass

1. Create `ReSTIR/<MethodName>/` with a `CMakeLists.txt` containing
   `add_plugin(<PassName>)`, `target_copy_shaders(<PassName> ReSTIR/<MethodName>)` and
   `target_source_group(<PassName> "ReSTIR")`.
   `add_plugin()` and `target_copy_shaders()` are global functions defined in the root
   CMakeLists.txt, so they work outside `Source/` just fine.
2. Add one line to `ReSTIR/CMakeLists.txt`: `add_subdirectory(<MethodName>)`.
3. The shader path on the C++ side must match the output path given to
   `target_copy_shaders` (e.g. `"ReSTIR/<MethodName>/Foo.cs.slang"`).

## Running

```
build/windows-vs2022/bin/Release/Mogwai.exe --script=ReSTIR/script/ReSTIRDI.py
```

Related study notes: `Media/MediaStudy/ReSTIR/`
