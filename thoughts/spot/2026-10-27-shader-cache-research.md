# Metal shader cache findings (librashader v0.12.1, build/librashader-src)

## Per-pass stages, Metal runtime
1. Preset load + preprocess (#include, #pragma, stage split): ShaderPresetPack::load_from_preset (librashader-runtime-mtl/src/filter_chain.rs:129, :288); librashader-preprocess/src/lib.rs:87 load_shader_source -> pragma.rs / stage.rs process_stages (:92).
2. glslang GLSL -> SPIR-V (vertex+fragment): librashader-reflect/src/reflect/presets.rs:~85 `I::Compiler::compile(source)` -> front/glslang.rs:28-34 compile_spirv. Called from mtl compile_passes, mtl filter_chain.rs:55-66 (uses uncached SpirvCompilation).
3. SPIR-V parse + reflect (SPIRV-Cross): presets.rs `T::from_compilation` (back/msl.rs:28-44 FromCompilation<SpirvCompilation,SpirvCross> for MSL); reflect at mtl filter_chain.rs:185.
4. SPIR-V -> MSL text (SPIRV-Cross, MSL 2.0): mtl filter_chain.rs:187 `reflect.compile(Some(MslVersion::new(2,0,0)))`.
5. MSL source -> MTLLibrary x2 per pass (vertex, fragment): graphics_pipeline.rs:62 and :68 newLibraryWithSource_options_error(.., None).
6. Pipeline state: graphics_pipeline.rs:146 newRenderPipelineStateWithDescriptor_error (create_pipeline at :115). Pass loop = filter_chain.rs:175-215 (init_passes), sequential ("todo: fix this to allow send" :180).
Mtl Cargo.toml has no librashader-cache dependency (vk/gl have it at Cargo.toml:23/:21).

## librashader-cache wiring (reference: d3d12, d3d9, vk, gl)
- Store: persy DB `librashader.db.1` in platform cache dir (~/Library/Caches/librashader on macOS), librashader-cache/src/cache.rs:15-30 get_cache_dir, :71-95 get_cache (process-wide OnceLock), get_blob :113, set_blob :128. Self-heals on panic (remove_cache :56).
- Key: blake3 over CacheKey bytes (cache.rs ~:175; key.rs: u32,i32,&[u8],Vec<u8>,Vec<u32>,&str). Value: Cacheable bytes (cacheable.rs:3-10).
- API: cache_shader_object(index, keys, factory, load, bypass) cache.rs:~148; cache_shader_object_deferred; cache_pipeline (d3d12 use graphics_pipeline.rs:240: caches PSO blob keyed by shaders+format).
- CachedCompilation<SpirvCompilation> (compilation.rs:12-61): wraps Glslang::compile; key = blake3(vertex+fragment GLSL), index "spirv", bincode of SpirvCompilation. Skips stage 2 only. Selected per runtime via `if !disable_cache` generic switch (d3d12 filter_chain.rs:196-208, d3d9 :83).
- Backend forwarding impls exist only for DXIL, HLSL, GLSL, SPIRV (compilation.rs:63-139). NO impl for MSL -> CachedCompilation cannot be used by Metal today.
- Reflect crate already has serde feature on SpirvCompilation (front/mod.rs:36,47); cache crate enables it. persy/blake3/bincode are platform-neutral (d3d module is windows-gated only).

## C API option shape
- d3d12 options.rs:20 `pub disable_cache: bool`; capi runtime/d3d12/filter_chain.rs:156 field, :164 `config_struct!{ 0 => [force_hlsl_pipeline, force_no_mipmaps, disable_cache]; 3 => [frames_in_flight]; }`. ctypes.rs:295-306 documents versioning: undeclared fields inherit Default; a field added in a later API version defaults to old behaviour.
- Metal: capi runtime/mtl/filter_chain.rs:98,103 only `0 => [force_no_mipmaps]`; Rust options.rs `FilterChainOptionsMetal { force_no_mipmaps }`.
  Mirror: add `disable_cache: bool` as API version 1 field (ver 0 -> true/disabled per ctypes.rs:301 convention), or a consumer-side path.

## What a Metal cache would skip
(a) CachedCompilation for MSL (SPIR-V keyed by GLSL hash): skips stage 2 (glslang). Needs: add `impl FromCompilation<CachedCompilation<SpirvCompilation>,T> for MSL` in librashader-cache/compilation.rs (copy of the HLSL block, ~15 lines), add librashader-cache dep + `disable_cache` option in mtl, switch compile_passes generic (mtl filter_chain.rs:55-66) like d3d12. ~60-80 lines across crates. Stages 3-6 still run.
(b) Cache MSL text (extra Cacheable String, key = SPIR-V hash + MslVersion): skips stage 4 only; needs stage 3 still for reflection, so low value alone.
(c) MTLBinaryArchive (per pipeline descriptor; skips AIR->GPU-binary part of stage 6, and when library creation is from archive-held functions also reduces 5). Needs descriptor.setBinaryArchives + archive serialize to URL; objc2-metal binding for MTLBinaryArchive. Does NOT skip stages 1-4 and MSL->AIR front-end of stage 5 (Metal still needs a MTLLibrary; fix: compile once to a .metallib via newLibraryWithData, store bytes, load with newLibraryWithData -- skips MSL parse/AIR gen). Larger patch (~150+ lines, unsafe objc2 plumbing, macOS-version gating).
Caveat (unverified, not measured): macOS has a system-wide Metal shader cache (in /var/folders/.../com.apple.metal/) keyed by MSL source hash that already makes repeat newLibraryWithSource and pipeline compiles cheaper on warm runs. So warm 2.2-3.0 s is probably dominated by CPU-side stages 1-4 (preprocess, glslang, SPIRV-Cross on Mega Bezel's huge sources, N passes), which the system cache does not touch; cold ~15 s = Metal compiler populating that cache (stages 5-6). Measure before deciding: time stages 2, 3+4, 5, 6 per pass with Instant.

## Recommendation
Do (a) first: smallest patch, reuses existing helper, same disk store, same C-API `disable_cache` shape. If measurement shows 3+4 still dominate after (a), extend cache to cache the MSL strings plus the serialized reflection (needs serde on ShaderReflection; larger). Avoid MTLBinaryArchive unless cold-start (~15 s on a fresh machine) matters; the OS cache handles repeat launches.
Where: librashader-cache (MSL forwarding impl), librashader-runtime-mtl (dep, options.rs, filter_chain.rs compile_passes, graphics_pipeline untouched), librashader-capi/runtime/mtl (field in config_struct version 1). Patch carried in scripts/librashader.sh as a .patch applied to the checkout.

## Upstream
Latest release v0.12.1 (2026-10-11) is the checked-out tag; last master commits 2026-10-11 are release/presets/capi fixes, none touch runtime-mtl caching. GitHub issue search "metal cache": 0 relevant (only #204 GL). No open upstream work found (checked via gh api; PR list not exhaustively checked).
