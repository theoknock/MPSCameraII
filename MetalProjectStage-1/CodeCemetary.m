//
//  CodeCemetary.m
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 7/2/21.
//

#import <Foundation/Foundation.h>
/**
 
 Left-over MPSImage filter code
 
 */
//        MPSImageGaussianBlur *gaussian_filter = [[MPSImageGaussianBlur alloc] initWithDevice:device sigma:5];
//        MPSImageMedian *filter2 = [[MPSImageMedian alloc] initWithDevice:device kernelDiameter:9];
//        MPSImageAreaMax *filter3 = [[MPSImageAreaMax alloc] initWithDevice:device kernelWidth:7 kernelHeight:17];
//        float linearGrayColorTransformValues[3] = {0.5f, 0.5f, 0.5f};
//        MPSImageSobel *sobel_filter = [[MPSImageSobel alloc] initWithDevice:device linearGrayColorTransform:linearGrayColorTransformValues];
//        const float convolutionWeights[] =  {
//            -1, 0, 1,
//            -2, 0, 2,
//            -1, 0, 1
//        };
//        MPSImageConvolution *convolution_edge = [[MPSImageConvolution alloc] initWithDevice:device kernelWidth:3 kernelHeight:3 weights:convolutionWeights];

//                [gaussian_filter encodeToCommandBuffer:commandBuffer inPlaceTexture:&(sourceTexture) fallbackCopyAllocator:nil];
//                [filter2 encodeToCommandBuffer:commandBuffer inPlaceTexture:&(sourceTexture) fallbackCopyAllocator:nil];
//                [filter3 encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture destinationTexture:destinationTexture];
//                [filter3 encodeToCommandBuffer:commandBuffer inPlaceTexture:&(sourceTexture) fallbackCopyAllocator:nil];
//                [calculation encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
//                [equalization encodeTransformToCommandBuffer:commandBuffer sourceTexture:sourceTexture histogram:histogramInfoBuffer histogramOffset:0];
//                [equalization encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture destinationTexture:destinationTexture];
//                [sobel_filter encodeToCommandBuffer:commandBuffer inPlaceTexture:&(destinationTexture) fallbackCopyAllocator:nil];
//                [convolution_edge encodeToCommandBuffer:commandBuffer inPlaceTexture:&(destinationTexture) fallbackCopyAllocator:nil];

/**
 
 Retains a Metal-compatible GPU device for the life of the class instance and automatically deallocates (even in non-ARC environments)
 Use to capture non-class or instance (i.e., local) properties for use outside of lexical declarative scope
 
 */

// @property (strong, nonatomic, setter=setDevice:) id<MTLDevice>_Nonnull(^_Nonnull device)(void);

//@synthesize device = _device;
//
//- (id<MTLDevice>  _Nonnull (^)(void))device {
//    return _device;
//}
//
//- (void)setDevice:(id<MTLDevice>  _Nonnull (^)(void))device {
//    device = _device;
//}
//        _device =
//        ^ (id<MTLDevice> _Nonnull device) {
//            return ^ id<MTLDevice> (void) {
//                return device;
//            };
//        }(view.device);


