#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const LBFilterChainErrorDomain;

/// A librashader Metal filter chain loaded from a .slangp preset.
@interface LBFilterChain : NSObject

/// Number of successful renderSource calls (test sentinel: proves librashader ran).
@property (nonatomic, readonly) NSUInteger frameCallCount;

/// Loads the preset with librashader's shader cache on.
- (nullable instancetype)initWithPresetPath:(NSString *)path
                                      queue:(id<MTLCommandQueue>)queue
                                      error:(NSError **)error;
/// Loads the preset. With `shaderCache` on, compiled passes are read from and written to
/// librashader's cache in ~/Library/Caches/librashader, so a preset loads much faster after
/// its first load; off, every pass is compiled from source.
- (nullable instancetype)initWithPresetPath:(NSString *)path
                                      queue:(id<MTLCommandQueue>)queue
                                shaderCache:(BOOL)shaderCache
                                      error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Encodes the chain's passes into the command buffer, drawing source into target.
- (BOOL)renderSource:(id<MTLTexture>)source
            toTarget:(id<MTLTexture>)target
       commandBuffer:(id<MTLCommandBuffer>)commandBuffer
            viewport:(CGRect)viewport
          frameCount:(NSUInteger)frameCount
               error:(NSError **)error;

- (void)setParameter:(NSString *)name value:(float)value;

/// The current value of a shader parameter, or nil when the chain has no parameter of that name.
- (nullable NSNumber *)parameter:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
