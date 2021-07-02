//
//  Renderer.m
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/2/21.
//

#import <simd/simd.h>
#import <ModelIO/ModelIO.h>

#import "Renderer.h"
#import "Camera.h"

#import "ShaderTypes.h"

static const NSUInteger MaxBuffersInFlight = 3;

@interface Renderer ()

@property (strong, nonatomic, setter=setDevice:) id<MTLDevice>_Nonnull(^_Nonnull device)(void);
@property (strong, nonatomic, setter=setDrawTexture:) void(^draw_texture)(void);
@property (strong, nonatomic, setter=setRenderTexture:) id<MTLTexture>_Nonnull(^ _Nonnull render_texture)(void);
@property (strong, nonatomic, setter=setTextureCache:) CVMetalTextureCacheRef _Nonnull(^ _Nonnull texture_cache)(void);
@property (strong, nonatomic, setter=setFilterTexture:) void(^filter_texture)(id<MTLCommandBuffer> commandBuffer, id<MTLTexture> sourceTexture, id<MTLTexture> destinationTexture);

@end

@implementation Renderer
{
dispatch_semaphore_t _inFlightSemaphore;
id <MTLCommandQueue> _commandQueue;

uint8_t _uniformBufferIndex;
matrix_float4x4 _projectionMatrix;
id <MTLBuffer> _dynamicUniformBuffer[MaxBuffersInFlight];
__block PerFrameDynamicUniforms perFrameDynamicUniforms;
MTLVertexDescriptor *_mtlVertexDescriptor;

id <MTLRenderPipelineState> _pipelineState;
id <MTLDepthStencilState> _depthState;
id <MTLSamplerState> _samplerState;

MTKMesh *_mesh;
id <MTLTexture> _inPlaceTexture;

MPSImageHistogram * imageHistogram;
MPSImageHistogramEqualization * imageHistogramEqualization;
}

@synthesize
device         = _device,
draw_texture   = _draw_texture,
render_texture = _render_texture,
texture_cache  = _texture_cache,
filter_texture = _filter_texture;

- (id<MTLDevice>  _Nonnull (^)(void))device {
    return _device;
}

- (void)setDevice:(id<MTLDevice>  _Nonnull (^)(void))device {
    device = _device;
}

- (void)setDrawTexture:(void (^)(void))draw_texture {
    _draw_texture = draw_texture;
}

- (void (^)(void))draw_texture {
    return _draw_texture;
}

- (void)setRenderTexture:(id<MTLTexture>  _Nonnull (^)(void))render_texture {
    _render_texture = render_texture;
    _draw_texture();
}

- (id<MTLTexture>  _Nonnull (^)(void))render_texture {
    return _render_texture;
}

- (void)setTextureCache:(CVMetalTextureCacheRef  _Nonnull (^)(void))texture_cache {
    _texture_cache = texture_cache;
}

- (CVMetalTextureCacheRef  _Nonnull (^)(void))texture_cache {
    return _texture_cache;
}

- (void)setFilterTexture:(void (^)(id<MTLCommandBuffer>, id<MTLTexture>, id<MTLTexture>))filter_texture {
    _filter_texture = filter_texture;
}

- (void (^)(id<MTLCommandBuffer>, id<MTLTexture>, id<MTLTexture>))filter_texture {
    return _filter_texture;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    self = [super init];
    if(self)
    {
        _inFlightSemaphore = dispatch_semaphore_create(MaxBuffersInFlight);
        [self _loadMetalWithView:view];
        [self _initInPlaceTexture];
        [self _loadMPSFilters];
        
        CFStringRef textureCacheKeys[2] = {kCVMetalTextureCacheMaximumTextureAgeKey, kCVMetalTextureUsage};
        float maximumTextureAge = (1.0 / view.preferredFramesPerSecond);
        CFNumberRef maximumTextureAgeValue = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloatType, &maximumTextureAge);
        MTLTextureUsage textureUsage = MTLTextureUsageShaderRead;
        CFNumberRef textureUsageValue = CFNumberCreate(NULL, kCFNumberNSIntegerType, &textureUsage);
        CFTypeRef textureCacheValues[2] = {maximumTextureAgeValue, textureUsageValue};
        CFIndex textureCacheAttributesCount = 2;
        CFDictionaryRef cacheAttributes = CFDictionaryCreate(NULL, (const void **)textureCacheKeys, (const void **)textureCacheValues, textureCacheAttributesCount, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        __block CVMetalTextureCacheRef textureCache;
        CVMetalTextureCacheCreate(NULL, cacheAttributes, _device(), NULL, &textureCache);
        CFShow(cacheAttributes);
        CFRelease(textureUsageValue);
        CFRelease(cacheAttributes);
        
        _texture_cache =
        ^ (CVMetalTextureCacheRef texture_cache) {
            return ^ CVMetalTextureCacheRef (void) {
                return texture_cache;
            };
        }(textureCache);
        
        [[Camera video] setVideoOutputDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate> _Nullable)self];
    }
    
    return self;
}

- (void)_loadMetalWithView:(nonnull MTKView *)view;
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
    
    _device =
    ^ (id<MTLDevice> _Nonnull device) {
        return ^ id<MTLDevice> (void) {
            return device;
        };
    }(view.device);
    
    _draw_texture = ^ (MTKView * view) {
        return ^ (void) {
            id<MTLTexture> texture = _render_texture();
            id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
            id<CAMetalDrawable> layerDrawable = [(CAMetalLayer *)(view.layer) nextDrawable];
            id<MTLTexture> drawingTexture = [layerDrawable texture]; //view.currentDrawable.texture;
            
            _filter_texture(commandBuffer, texture, drawingTexture);
            
            [commandBuffer presentDrawable:layerDrawable];  // view.currentDrawable];
            [commandBuffer commit];
        };
    }(view);
    
    _commandQueue = [_device() newCommandQueue];
}

- (void)_initInPlaceTexture {
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.textureType = MTLTextureType2D;
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    textureDescriptor.width = 2160.0;
    textureDescriptor.height = 3840.0;
    textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    _inPlaceTexture = [_device() newTextureWithDescriptor:textureDescriptor];
}

- (void)_loadMPSFilters {
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
        
        //        MPSImageGaussianBlur *gaussian_filter = [[MPSImageGaussianBlur alloc] initWithDevice:device sigma:5];
        //        MPSImageMedian *filter2 = [[MPSImageMedian alloc] initWithDevice:device kernelDiameter:9];
        //        MPSImageAreaMax *filter3 = [[MPSImageAreaMax alloc] initWithDevice:device kernelWidth:7 kernelHeight:17];
        float linearGrayColorTransformValues[3] = {0.5f, 0.5f, 0.5f};
        MPSImageSobel *sobel_filter = [[MPSImageSobel alloc] initWithDevice:device linearGrayColorTransform:linearGrayColorTransformValues];
        const float convolutionWeights[] =  {
            -1, 0, 1,
            -2, 0, 2,
            -1, 0, 1
        };
        MPSImageConvolution *convolution_edge = [[MPSImageConvolution alloc] initWithDevice:device kernelWidth:3 kernelHeight:3 weights:convolutionWeights];
        return ^ (void) {
            return ^ (id<MTLCommandBuffer> commandBuffer, id<MTLTexture> sourceTexture, id<MTLTexture> destinationTexture) {
                //                [gaussian_filter encodeToCommandBuffer:commandBuffer inPlaceTexture:&(sourceTexture) fallbackCopyAllocator:nil];
                //                [filter2 encodeToCommandBuffer:commandBuffer inPlaceTexture:&(sourceTexture) fallbackCopyAllocator:nil];
                //                [filter3 encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture destinationTexture:destinationTexture];
                //                [filter3 encodeToCommandBuffer:commandBuffer inPlaceTexture:&(sourceTexture) fallbackCopyAllocator:nil];
                [calculation encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
                [equalization encodeTransformToCommandBuffer:commandBuffer sourceTexture:sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
                [equalization encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture destinationTexture:destinationTexture];
                [sobel_filter encodeToCommandBuffer:commandBuffer inPlaceTexture:&(destinationTexture) fallbackCopyAllocator:nil];
                [convolution_edge encodeToCommandBuffer:commandBuffer inPlaceTexture:&(destinationTexture) fallbackCopyAllocator:nil];
            };
        };
    }(_device());
    
    _filter_texture = filters();
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    [self setRenderTexture:^ (CVMetalTextureCacheRef texture_cache_ref, CVPixelBufferRef pixel_buffer) {
        return ^id<MTLTexture> _Nonnull (void) {
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
    } (_texture_cache(), CMSampleBufferGetImageBuffer(sampleBuffer))];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    
}

@end
