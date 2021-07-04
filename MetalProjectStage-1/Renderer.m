//
//  Renderer.m
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/2/21.
//

#import "Renderer.h"
#import "Camera.h"

@implementation Renderer
{
    id<MTLTexture> (^create_texture)(CVPixelBufferRef);
    void (^(^filter_texture)(id<MTLTexture>))(id<MTLCommandBuffer>, id<MTLTexture>);
    void (^draw_texture)(void (^)(id<MTLCommandBuffer>, id<MTLTexture>));
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    if (self = [super init])
    {
        create_texture = ^ (CVMetalTextureCacheRef texture_cache_ref) {
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
        }(^ (id<MTLDevice> device) {
            CFStringRef textureCacheKeys[2] = {kCVMetalTextureCacheMaximumTextureAgeKey, kCVMetalTextureUsage};
            float maximumTextureAge = (1.0 / view.preferredFramesPerSecond);
            CFNumberRef maximumTextureAgeValue = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloatType, &maximumTextureAge);
            MTLTextureUsage textureUsage = MTLTextureUsageShaderRead;
            CFNumberRef textureUsageValue = CFNumberCreate(NULL, kCFNumberNSIntegerType, &textureUsage);
            CFTypeRef textureCacheValues[2] = {maximumTextureAgeValue, textureUsageValue};
            CFIndex textureCacheAttributesCount = 2;
            CFDictionaryRef cacheAttributes = CFDictionaryCreate(NULL, (const void **)textureCacheKeys, (const void **)textureCacheValues, textureCacheAttributesCount, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            
            CVMetalTextureCacheRef textureCache;
            CVMetalTextureCacheCreate(NULL, cacheAttributes, device, NULL, &textureCache);
            CFShow(cacheAttributes);
            CFRelease(textureUsageValue);
            CFRelease(cacheAttributes);
            return textureCache;
        }(view.preferredDevice));
        
        filter_texture = ^ (id<MTLDevice> device) {
            MPSImageHistogramInfo histogramInfo = {
                .numberOfHistogramEntries = 256,
                .histogramForAlpha = FALSE,
                .minPixelValue = simd_make_float4(0.0, 0.0, 0.0, 0.0),
                .maxPixelValue = simd_make_float4(1.0, 1.0, 1.0, 1.0)
            };
            MPSImageHistogram * calculation = [[MPSImageHistogram alloc] initWithDevice:device histogramInfo:&histogramInfo];
            MPSImageHistogramEqualization * equalization = [[MPSImageHistogramEqualization alloc] initWithDevice:calculation.device histogramInfo:&histogramInfo];
            size_t bufferLength = [calculation histogramSizeForSourceFormat:MTLPixelFormatBGRA8Unorm_sRGB];
            id<MTLBuffer> histogramInfoBuffer = [calculation.device newBufferWithLength:bufferLength options:MTLResourceStorageModePrivate];
            
            return ^ (id<MTLTexture> sourceTexture) {
                return ^ (id<MTLCommandBuffer> commandBuffer, id<MTLTexture> destinationTexture) {
                    [calculation encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
                    [equalization encodeTransformToCommandBuffer:commandBuffer sourceTexture:sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
                    [equalization encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture destinationTexture:destinationTexture];
                };
            };
        }(view.preferredDevice);
        
        draw_texture = ^ (MTKView * view, id<MTLCommandQueue> command_queue) {
            return ^ (void (^filter)(id<MTLCommandBuffer>, id<MTLTexture>)) {
                id<MTLCommandBuffer> commandBuffer = [command_queue commandBuffer];
                id<CAMetalDrawable> layerDrawable = [(CAMetalLayer *)(view.layer) nextDrawable];
                id<MTLTexture> drawableTexture = [layerDrawable texture];
                
                filter(commandBuffer, drawableTexture);
                
                [commandBuffer presentDrawable:layerDrawable];
                [commandBuffer commit];
            };
        }(view, [view.preferredDevice newCommandQueue]);
        
        [[Camera video] setVideoOutputDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate> _Nullable)self];
    }
    
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    draw_texture(filter_texture(create_texture(CMSampleBufferGetImageBuffer(sampleBuffer))));
}

@end
