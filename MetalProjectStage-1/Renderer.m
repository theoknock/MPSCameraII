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

@property (strong, nonatomic, setter=setDrawTexture:) void(^drawTexture)(void);
@property (strong, nonatomic, setter=setRenderTexture:) id<MTLTexture>_Nonnull(^ _Nonnull render_texture)(void);
@property (strong, nonatomic, setter=setTextureCache:) CVMetalTextureCacheRef _Nonnull(^ _Nonnull texture_cache)(void);
@property (strong, nonatomic, setter=setDevice:) id<MTLDevice>_Nonnull(^_Nonnull device)(void);
@property (strong, nonatomic, setter=setGlobalBlock:) void(^blk_global)(id<MTLCommandBuffer> commandBuffer, id<MTLTexture> * sourceTexture, id<MTLTexture> * destinationTexture);

@end

@implementation Renderer
{
dispatch_semaphore_t _inFlightSemaphore;
    //    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;
    
    uint8_t _uniformBufferIndex;
    matrix_float4x4 _projectionMatrix;
    id <MTLBuffer> _dynamicUniformBuffer[MaxBuffersInFlight];
    __block PerFrameDynamicUniforms perFrameDynamicUniforms;
    MTLVertexDescriptor *_mtlVertexDescriptor;
    
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    
    MTKMesh *_mesh;
    id <MTLTexture> _colorMap;
    
    MPSImageHistogram * imageHistogram;
    MPSImageHistogramEqualization * imageHistogramEqualization;
}

@synthesize
device         = _device,
drawTexture    = _drawTexture,
render_texture = _render_texture,
texture_cache  = _texture_cache,
blk_global     = _blk_global;

- (id<MTLDevice>  _Nonnull (^)(void))device {
    return _device;
}

- (void)setDevice:(id<MTLDevice>  _Nonnull (^)(void))device {
    device = _device;
}

- (void)setDrawTexture:(void (^)(void))drawTexture {
    drawTexture = _drawTexture;
}

-(void (^)(void))drawTexture {
    return _drawTexture;
}

- (void)setRenderTexture:(id<MTLTexture>  _Nonnull (^)(void))render_texture {
    _render_texture = render_texture;
    _drawTexture();
}

- (void)setTextureCache:(CVMetalTextureCacheRef  _Nonnull (^)(void))texture_cache {
    _texture_cache = texture_cache;
}

- (CVMetalTextureCacheRef  _Nonnull (^)(void))texture_cache {
    return _texture_cache;
}

- (void)setGlobalBlock:(void (^)(id<MTLCommandBuffer>, id<MTLTexture> *, id<MTLTexture> *))blk_global {
    _blk_global = blk_global;
}

- (void (^)(id<MTLCommandBuffer>, id<MTLTexture> *, id<MTLTexture> *))blk_global {
    return _blk_global;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    self = [super init];
    if(self)
    {
        _device =
        ^ (id<MTLDevice> _Nonnull device) {
            return ^ id<MTLDevice> (void) {
                return device;
            };
        }(view.preferredDevice);
        
        _inFlightSemaphore = dispatch_semaphore_create(MaxBuffersInFlight);
        [self _loadMetalWithView:view];
        [self _loadAssets];
        [self histogramEqualization];
        
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
    [view setFramebufferOnly:FALSE];
    
    _drawTexture = ^ (MTKView * view, PerFrameDynamicUniforms * dynamic_uniforms) {
        return ^ (void) {
            (* dynamic_uniforms).counter++;
            (* dynamic_uniforms).rotation = (float)((* dynamic_uniforms).counter % NSUIntegerMax) / view.preferredFramesPerSecond;
            [view draw];
        };
    }(view, &perFrameDynamicUniforms);
    
    for(NSUInteger i = 0; i < MaxBuffersInFlight; i++)
    {
        _dynamicUniformBuffer[i] = [_device() newBufferWithLength:sizeof(Uniforms)
                                                        options:MTLResourceStorageModeShared];
        _dynamicUniformBuffer[i].label = @"UniformBuffer";
    }
    
    _mtlVertexDescriptor = [[MTLVertexDescriptor alloc] init];
    
    _mtlVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexMeshPositions;
    
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].format = MTLVertexFormatFloat2;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].bufferIndex = BufferIndexMeshGenerics;
    
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stride = 12;
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stepFunction = MTLVertexStepFunctionPerVertex;
    
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stride = 8;
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stepFunction = MTLVertexStepFunctionPerVertex;
    
    id<MTLLibrary> defaultLibrary = [_device() newDefaultLibrary];
    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
    id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];
    
    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device() newDepthStencilStateWithDescriptor:depthStateDesc];
    
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"MyPipeline";
    pipelineStateDescriptor.sampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.vertexDescriptor = _mtlVertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    
    NSError *error = NULL;
    _pipelineState = [_device() newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState)
    {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }
    
    _commandQueue = [_device() newCommandQueue];
}

- (void)_loadAssets
{
    NSError *error;
    
    MTKMeshBufferAllocator *metalAllocator = [[MTKMeshBufferAllocator alloc]
                                              initWithDevice: _device()];
    
    MDLMesh *mdlMesh = [MDLMesh newBoxWithDimensions:(vector_float3){4, 4, 4}
                                            segments:(vector_uint3){2, 2, 2}
                                        geometryType:MDLGeometryTypeTriangles
                                       inwardNormals:NO
                                           allocator:metalAllocator];
    
    MDLVertexDescriptor *mdlVertexDescriptor =
    MTKModelIOVertexDescriptorFromMetal(_mtlVertexDescriptor);
    
    mdlVertexDescriptor.attributes[VertexAttributePosition].name  = MDLVertexAttributePosition;
    mdlVertexDescriptor.attributes[VertexAttributeTexcoord].name  = MDLVertexAttributeTextureCoordinate;
    
    mdlMesh.vertexDescriptor = mdlVertexDescriptor;
    
    _mesh = [[MTKMesh alloc] initWithMesh:mdlMesh
                                   device:_device()
                                    error:&error];
    
    if(!_mesh || error)
    {
        NSLog(@"Error creating MetalKit mesh %@", error.localizedDescription);
    }
}

- (void)histogramEqualization {
    MPSImageHistogramInfo histogramInfo = {
        .numberOfHistogramEntries = 256,
        .histogramForAlpha = FALSE,
        .minPixelValue = simd_make_float4(0.0, 0.0, 0.0, 0.0),
        .maxPixelValue = simd_make_float4(1.0, 1.0, 1.0, 1.0)
    };
    MPSImageHistogram * calculation = [[MPSImageHistogram alloc] initWithDevice:_device() histogramInfo:&histogramInfo];
    MPSImageHistogramEqualization * equalization = [[MPSImageHistogramEqualization alloc] initWithDevice:_device() histogramInfo:&histogramInfo];
    
    MPSImageHistogram * (^histogram_calculator)(void) =
    ^ (MPSImageHistogram * calculator) {
        return ^ MPSImageHistogram * (void) {
            return calculator;
        };
    }(calculation);
    
    MPSImageHistogramEqualization * (^histogram_equalizer)(void) =
    ^ (MPSImageHistogramEqualization * equalizer) {
        return ^ MPSImageHistogramEqualization * (void) {
            return equalizer;
        };
    }(equalization);
    
    MPSCopyAllocator myAllocator = ^id <MTLTexture>(MPSKernel * __nonnull filter, __nonnull id <MTLCommandBuffer> cmdBuf, __nonnull id <MTLTexture> sourceTexture)
    {
        MTLPixelFormat format = sourceTexture.pixelFormat;
        MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: format width: sourceTexture.width height: sourceTexture.height mipmapped: NO];
     
        id <MTLTexture> result = [cmdBuf.device newTextureWithDescriptor: d];
     
        return result;
        // d is autoreleased.
    };
    
    void(^(^blk_local)(void))(id<MTLCommandBuffer>, id<MTLTexture> *, id<MTLTexture> *) = ^ (MPSImageHistogram * calculate_histogram, MPSImageHistogramEqualization * equalize_histogram) {
        return ^ (void) {
            return ^ (id<MTLCommandBuffer> commandBuffer, id<MTLTexture> * sourceTexture, id<MTLTexture> * destinationTexture) {
                size_t bufferLength = [calculation histogramSizeForSourceFormat:(*sourceTexture).pixelFormat];
                id<MTLBuffer> histogramInfoBuffer = [calculation.device newBufferWithLength:bufferLength options:MTLResourceStorageModePrivate];
                [calculation encodeToCommandBuffer:commandBuffer sourceTexture:*sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
                [equalization encodeTransformToCommandBuffer:commandBuffer sourceTexture:*sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
                [equalization encodeToCommandBuffer:commandBuffer sourceTexture:*sourceTexture destinationTexture:*destinationTexture];
            };
        };
    }(calculation, equalization);
    
    _blk_global = blk_local();
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    [self setRenderTexture:^ (CVMetalTextureCacheRef texture_cache_ref) {
        return ^id<MTLTexture> _Nonnull(void) {
            CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            id<MTLTexture> texture = nil;
            {
                MTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;
                CVMetalTextureRef metalTextureRef = NULL;
                CVMetalTextureCacheCreateTextureFromImage(NULL, texture_cache_ref, pixelBuffer, NULL, pixelFormat, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &metalTextureRef);
                texture = CVMetalTextureGetTexture(metalTextureRef);
                CFRelease(metalTextureRef);
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            return texture;
        };
    } (_texture_cache())];
}

//void MyBlurTextureInPlace(id <MTLTexture> __strong *inTexture, float blurRadius, id<MTLDevice> d, id <MTLCommandQueue> q, )
//{
//    id <MTLCommandBuffer> buffer = [q commandBuffer];
//
//    MPSImageGaussianBlur *blur = [[MPSImageGaussianBlur alloc] initWithDevice:d sigma:blurRadius];
//    if( nil == blur )
//        NSLog(@"%s", __PRETTY_FUNCTION__);
//
//    [blur encodeToCommandBuffer:buffer inPlaceTexture:inTexture copyAllocator:^id <MTLTexture>(MPSKernel * __nonnull filter, __nonnull id <MTLCommandBuffer> cmdBuf, __nonnull id <MTLTexture> sourceTexture)
//    {
//        MTLPixelFormat format = sourceTexture.pixelFormat;
//        MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: format width: sourceTexture.width height: sourceTexture.height mipmapped: NO];
//
//        id <MTLTexture> result = [cmdBuf.device newTextureWithDescriptor: d];
//
//        return result;
//    }];
//
//    // The usual Metal enqueue process.
//    [buffer waitUntilCompleted];
//}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
    
    _uniformBufferIndex = (_uniformBufferIndex + 1) % MaxBuffersInFlight;
    
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    [commandBuffer enqueue];
    
    id<MTLTexture> sourceTexture = _render_texture();
    id<MTLTexture> destinationTexture = [view.currentDrawable texture];
    
    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
        dispatch_semaphore_signal(block_sema);
    }];
    
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    
    if(renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";
        
        [renderEncoder pushDebugGroup:@"DrawBox"];
        
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthState];
        
        [renderEncoder setVertexBuffer:_dynamicUniformBuffer[_uniformBufferIndex]
                                offset:0
                               atIndex:BufferIndexUniforms];
        
        {
            [renderEncoder setVertexBytes:&perFrameDynamicUniforms
                                   length:sizeof(perFrameDynamicUniforms)
                                  atIndex:BufferIndexPerFrameDynamicUniforms];
        }
        
        [renderEncoder setFragmentBuffer:_dynamicUniformBuffer[_uniformBufferIndex]
                                  offset:0
                                 atIndex:BufferIndexUniforms];
        
        for (NSUInteger bufferIndex = 0; bufferIndex < _mesh.vertexBuffers.count; bufferIndex++)
        {
            MTKMeshBuffer *vertexBuffer = _mesh.vertexBuffers[bufferIndex];
            if((NSNull*)vertexBuffer != [NSNull null])
            {
                [renderEncoder setVertexBuffer:vertexBuffer.buffer
                                        offset:vertexBuffer.offset
                                       atIndex:bufferIndex];
            }
        }
        
        [renderEncoder setFragmentTexture:sourceTexture
                                  atIndex:TextureIndexColor];
        
        for(MTKSubmesh *submesh in _mesh.submeshes)
        {
            [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                      indexCount:submesh.indexCount
                                       indexType:submesh.indexType
                                     indexBuffer:submesh.indexBuffer.buffer
                               indexBufferOffset:submesh.indexBuffer.offset];
        }
        
        [renderEncoder popDebugGroup];
        
        [renderEncoder endEncoding];
        
        _blk_global(commandBuffer, &sourceTexture, &destinationTexture);
        
        [commandBuffer presentDrawable:view.currentDrawable];
        
        
    }
    
    [commandBuffer commit];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    float aspect = size.width / (float)size.height;
    _projectionMatrix = matrix_perspective_right_hand(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
    
    for (NSUInteger bufferIndex = 0; bufferIndex < 3; bufferIndex++) {
        Uniforms * uniforms = (Uniforms*)_dynamicUniformBuffer[bufferIndex].contents;
        
        uniforms->projectionMatrix = _projectionMatrix;
        
        vector_float3 rotationAxis = {1, 1, 0};
        matrix_float4x4 modelMatrix = matrix4x4_rotation((1.0 / view.preferredFramesPerSecond), rotationAxis);
        matrix_float4x4 viewMatrix = matrix4x4_translation(0.0, 0.0, -8.0);
        
        uniforms->modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix);
    }
}

#pragma mark Matrix Math Utilities

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz)
{
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis)
{
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;
    
    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0},
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0},
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0},
        {                   0,                   0,                   0, 1}
    }};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    
    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}


@end
