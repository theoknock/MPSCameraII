//
//  Renderer.m
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/2/21.
//
// A leaner, meaner approach to using Metal Performance Shaders for performing image-processing techniques to live video.
// It is able to apply histogram equalization to 60 frames per second of live video at a resolution of 3840 X 2160 using between 6% and 12% of the CPU.
// That is expected to drop precipitously as development continues.
// It is resource-tight: Any object needing allocation once is allocated once and reused; as soon as an allocated object is no longer needed, it is disposed of automatically whether ARC is enabled or otherwise
// De minimus execution calls (for example: the MTKViewDelegate protocol methods have been replaced with block equivalents without sacrificing any functionality)
// (there's much more to it than this...)
// Its component-based programming model affords easy adaptation to any input and output
//

// The key components in the image-processing chain are:
// render_texture converts a CMSampleBuffer to an id<MTLTexture>
// filter_texture processes the id<MTLTexture> using Metal Performance Shaders
// draw_texture displays the id<MTLTexture>
//
// The mutable components form a single, immutable image-processing chain (or pipe), which starts with input from a source (video, photos) and ends with output to a destination (screen, storage).
//
// The components and their order are statically defined; however, each component can be modified to render, filter and draw a texture from any source to any output.
// For example:
// render_texture can be modified to convert a UIImage to an id<MTLTexture>;
// filter_texture can be modified to use Core Image or Metal vertex, fragment and/or compute (kernel) functions
// draw_texture can be modified to write the texture to a file


#import "Renderer.h"
#import "Camera.h"

@implementation Renderer
{
    id<MTLTexture> _Nonnull (^ _Nonnull _render_texture)(CVPixelBufferRef pixel_buffer);
    void (^_draw_texture)(id<MTLTexture> texture);
    void (^_filter_texture)(id<MTLCommandBuffer> commandBuffer, id<MTLTexture> sourceTexture, id<MTLTexture> destinationTexture);
}

//@synthesize
//draw_texture   = _draw_texture,
//render_texture = _render_texture,
//filter_texture = _filter_texture;
//
//- (void)setDrawTexture:(void (^)(id<MTLTexture>))draw_texture {
//    _draw_texture = draw_texture;
//}
//
//- (void (^)(id<MTLTexture>))draw_texture {
//    return _draw_texture;
//}
//
//- (void)setRenderTexture:(id<MTLTexture>  _Nonnull (^)(CVPixelBufferRef))render_texture {
//    _render_texture = render_texture;
//}
//
//- (id<MTLTexture>  _Nonnull (^)(CVPixelBufferRef))render_texture {
//    return _render_texture;
//}
//
//- (void)setFilterTexture:(void (^)(id<MTLCommandBuffer>, id<MTLTexture>, id<MTLTexture>))filter_texture {
//    _filter_texture = filter_texture;
//}
//
//- (void (^)(id<MTLCommandBuffer>, id<MTLTexture>, id<MTLTexture>))filter_texture {
//    return _filter_texture;
//}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    if (self = [super init])
    {        
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
                // The command buffer and drawable have to be declared inside the draw_texture block because
                // additional processing may be performed before or after filter_texture executes
                id<MTLCommandBuffer> commandBuffer = [command_queue commandBuffer];
                id<CAMetalDrawable> layerDrawable = [(CAMetalLayer *)(view.layer) nextDrawable];
                id<MTLTexture> drawableTexture = [layerDrawable texture];
                
                _filter_texture(commandBuffer, texture, drawableTexture);
                
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

@end
