#define LIBRA_RUNTIME_METAL
#import "LibrashaderBridge.h"
#import "librashader.h"

// librashader.h only declares function-pointer typedefs (it is built for the dynamic loader),
// so the exported symbols of librashader.dylib are declared here with the same signatures.
extern libra_error_t libra_preset_create(const char *filename, libra_shader_preset_t *out);
extern libra_error_t libra_preset_free(libra_shader_preset_t *preset);
extern libra_error_t libra_mtl_filter_chain_create(libra_shader_preset_t *preset,
                                                   id<MTLCommandQueue> queue,
                                                   const struct filter_chain_mtl_opt_t *options,
                                                   libra_mtl_filter_chain_t *out);
extern libra_error_t libra_mtl_filter_chain_frame(libra_mtl_filter_chain_t *chain,
                                                  id<MTLCommandBuffer> command_buffer,
                                                  size_t frame_count, id<MTLTexture> image,
                                                  id<MTLTexture> output,
                                                  const struct libra_viewport_t *viewport,
                                                  const float *mvp,
                                                  const struct frame_mtl_opt_t *opt);
extern libra_error_t libra_mtl_filter_chain_set_param(libra_mtl_filter_chain_t *chain,
                                                      const char *param_name, float value);
extern libra_error_t libra_mtl_filter_chain_free(libra_mtl_filter_chain_t *chain);
extern int32_t libra_error_errno(libra_error_t error);
extern int32_t libra_error_write(libra_error_t error, char **out);
extern int32_t libra_error_free_string(char **out);
extern int32_t libra_error_free(libra_error_t *error);

NSErrorDomain const LBFilterChainErrorDomain = @"LBFilterChainErrorDomain";

/// Converts (and frees) a librashader error; returns YES when err was NULL.
static BOOL LBCheck(libra_error_t err, NSString *what, NSError **out) {
    if (err == NULL) return YES;
    NSInteger code = libra_error_errno(err);
    char *msg = NULL;
    NSString *text = @"unknown error";
    if (libra_error_write(err, &msg) == 0 && msg != NULL) {
        text = [NSString stringWithUTF8String:msg] ?: text;
        libra_error_free_string(&msg);
    }
    libra_error_free(&err);
    if (out) {
        *out = [NSError errorWithDomain:LBFilterChainErrorDomain code:code
                               userInfo:@{NSLocalizedDescriptionKey:
                                              [NSString stringWithFormat:@"%@: %@", what, text]}];
    }
    return NO;
}

@implementation LBFilterChain {
    libra_mtl_filter_chain_t _chain;
}

- (nullable instancetype)initWithPresetPath:(NSString *)path
                                      queue:(id<MTLCommandQueue>)queue
                                      error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    libra_shader_preset_t preset = NULL;
    if (!LBCheck(libra_preset_create(path.fileSystemRepresentation, &preset),
                 @"loading preset", error)) return nil;
    struct filter_chain_mtl_opt_t opt = { .version = LIBRASHADER_CURRENT_VERSION,
                                          .force_no_mipmaps = false };
    BOOL ok = LBCheck(libra_mtl_filter_chain_create(&preset, queue, &opt, &_chain),
                      @"creating Metal filter chain", error);
    if (preset) libra_preset_free(&preset);
    return ok ? self : nil;
}

- (BOOL)renderSource:(id<MTLTexture>)source
            toTarget:(id<MTLTexture>)target
       commandBuffer:(id<MTLCommandBuffer>)commandBuffer
            viewport:(CGRect)viewport
          frameCount:(NSUInteger)frameCount
               error:(NSError **)error {
    struct libra_viewport_t vp = { .x = (float)viewport.origin.x, .y = (float)viewport.origin.y,
                                   .width = (uint32_t)viewport.size.width,
                                   .height = (uint32_t)viewport.size.height };
    struct frame_mtl_opt_t opt = { .version = LIBRASHADER_CURRENT_VERSION, .frame_direction = 1,
                                   .total_subframes = 1, .current_subframe = 1,
                                   .frames_per_second = 60.0f };
    if (!LBCheck(libra_mtl_filter_chain_frame(&_chain, commandBuffer, frameCount, source, target,
                                              &vp, NULL, &opt), @"rendering frame", error))
        return NO;
    _frameCallCount++;
    return YES;
}

- (void)setParameter:(NSString *)name value:(float)value {
    libra_error_t err = libra_mtl_filter_chain_set_param(&_chain, name.UTF8String, value);
    if (err) libra_error_free(&err);
}

- (void)dealloc {
    if (_chain) libra_mtl_filter_chain_free(&_chain);
}

@end
