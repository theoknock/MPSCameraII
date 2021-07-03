//
//  Renderer.m
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/2/21.
//

#import <simd/simd.h>
#import "Renderer.h"
#import "Camera.h"

@interface Renderer ()

@property (strong, nonatomic, setter=setRenderTexture:) id<MTLTexture>_Nonnull(^ _Nonnull render_texture)(CVPixelBufferRef pixel_buffer);
@property (strong, nonatomic, setter=setDrawTexture:) void(^draw_texture)(id<MTLTexture> texture);
@property (strong, nonatomic, setter=setFilterTexture:) void(^filter_texture)(id<MTLCommandBuffer> commandBuffer, id<MTLTexture> sourceTexture, id<MTLTexture> destinationTexture);

@end

@implementation Renderer
{
    MPSImageHistogram * imageHistogram;
    MPSImageHistogramEqualization * imageHistogramEqualization;
}

@synthesize
draw_texture   = _draw_texture,
render_texture = _render_texture,
filter_texture = _filter_texture;

- (void)setDrawTexture:(void (^)(id<MTLTexture>))draw_texture {
    _draw_texture = draw_texture;
}

- (void (^)(id<MTLTexture>))draw_texture {
    return _draw_texture;
}

- (void)setRenderTexture:(id<MTLTexture>  _Nonnull (^)(CVPixelBufferRef))render_texture {
    _render_texture = render_texture;
}

- (id<MTLTexture>  _Nonnull (^)(CVPixelBufferRef))render_texture {
    return _render_texture;
}

- (void)setFilterTexture:(void (^)(id<MTLCommandBuffer>, id<MTLTexture>, id<MTLTexture>))filter_texture {
    _filter_texture = filter_texture;
}

- (void (^)(id<MTLCommandBuffer>, id<MTLTexture>, id<MTLTexture>))filter_texture {
    return _filter_texture;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    if (self = [super init])
    {
        view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        view.sampleCount = 1;
        [view setPaused:TRUE];
        [view setEnableSetNeedsDisplay:FALSE];
        [view setAutoResizeDrawable:FALSE];
        [view setFramebufferOnly:FALSE];
        [view setClearColor:MTLClearColorMake(1.0, 1.0, 1.0, 1.0)];
        [view setDevice:view.preferredDevice];
        
        void(^(^filters)(void))(id<MTLCommandBuffer>, id<MTLTexture>, id<MTLTexture>) = ^ (id<MTLDevice> device) {
            MPSImageHistogramInfo histogramInfo = {
                .numberOfHistogramEntries = 256,
                .histogramForAlpha = FALSE,
                .minPixelValue = simd_make_float4(0.0, 0.0, 0.0, 0.0),
                .maxPixelValue = simd_make_float4(1.0, 1.0, 1.0, 1.0)
            };
            MPSImageHistogram * calculation = [[MPSImageHistogram alloc] initWithDevice:device histogramInfo:&histogramInfo];
            MPSImageHistogramEqualization * equalization = [[MPSImageHistogramEqualization alloc] initWithDevice:device histogramInfo:&histogramInfo];
            size_t bufferLength = [calculation histogramSizeForSourceFormat:MTLPixelFormatBGRA8Unorm_sRGB];
            id<MTLBuffer> histogramInfoBuffer = [calculation.device newBufferWithLength:bufferLength options:MTLResourceStorageModePrivate];
            
            return ^ (void) {
                return ^ (id<MTLCommandBuffer> commandBuffer, id<MTLTexture> sourceTexture, id<MTLTexture> destinationTexture) {
                    [calculation encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
                    [equalization encodeTransformToCommandBuffer:commandBuffer sourceTexture:sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
                    [equalization encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture destinationTexture:destinationTexture];
                };
            };
        }(view.preferredDevice);
        
        _filter_texture = filters();
        
        _render_texture = ^ (CVMetalTextureCacheRef texture_cache_ref) {
            return ^id<MTLTexture> _Nonnull (CVPixelBufferRef pixel_buffer) {
                CVPixelBufferLockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
                id<MTLTexture> texture = nil;
                {
                    MTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;
                    CVMetalTextureRef metalTextureRef = NULL;
                    CVMetalTextureCacheCreateTextureFromImage(NULL, texture_cache_ref, pixel_buffer, NULL, pixelFormat, CVPixelBufferGetWidth(pixel_buffer), CVPixelBufferGetHeight(pixel_buffer), 0, &metalTextureRef);
                    texture = CVMetalTextureGetTexture(metalTextureRef);
                    CFRelease(metalTextureRef);
                }
                CVPixelBufferUnlockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
                return texture;
            };
        }(^ {
            CFStringRef textureCacheKeys[2] = {kCVMetalTextureCacheMaximumTextureAgeKey, kCVMetalTextureUsage};
            float maximumTextureAge = (1.0 / view.preferredFramesPerSecond);
            CFNumberRef maximumTextureAgeValue = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloatType, &maximumTextureAge);
            MTLTextureUsage textureUsage = MTLTextureUsageShaderRead;
            CFNumberRef textureUsageValue = CFNumberCreate(NULL, kCFNumberNSIntegerType, &textureUsage);
            CFTypeRef textureCacheValues[2] = {maximumTextureAgeValue, textureUsageValue};
            CFIndex textureCacheAttributesCount = 2;
            CFDictionaryRef cacheAttributes = CFDictionaryCreate(NULL, (const void **)textureCacheKeys, (const void **)textureCacheValues, textureCacheAttributesCount, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            
            CVMetalTextureCacheRef textureCache;
            CVMetalTextureCacheCreate(NULL, cacheAttributes, view.preferredDevice, NULL, &textureCache);
            CFShow(cacheAttributes);
            CFRelease(textureUsageValue);
            CFRelease(cacheAttributes);
            return textureCache;
        }());
        
        _draw_texture = ^ (MTKView * view, id<MTLCommandQueue> command_queue) {
            return ^ (id<MTLTexture> texture) {
                id<MTLCommandBuffer> commandBuffer = [command_queue commandBuffer];
                id<CAMetalDrawable> layerDrawable = [(CAMetalLayer *)(view.layer) nextDrawable];
                
                _filter_texture(commandBuffer, texture, [layerDrawable texture]);
                
                [commandBuffer presentDrawable:layerDrawable];
                [commandBuffer commit];
            };
        }(view, [view.preferredDevice newCommandQueue]);
        
        [[Camera video] setVideoOutputDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate> _Nullable)self];
    }
    
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    _draw_texture(_render_texture(CMSampleBufferGetImageBuffer(sampleBuffer)));
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    
}

@end
