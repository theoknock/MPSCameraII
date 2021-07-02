//
//  Camera.m
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/15/21.
//

#import "Camera.h"
#include "GlobalDispatch.h"

@interface Camera ()
{
    dispatch_queue_t videoOutputQueue;
    AVCaptureSession * captureSession;
    AVCaptureDevice * captureDevice;
    AVCaptureDeviceInput * captureInput;
//    AVCaptureVideoPreviewLayer *previewLayer;
    AVCaptureVideoDataOutput * captureOutput;
}

@end

@implementation Camera

@synthesize videoOutputDelegate = _videoOutputDelegate;

static Camera *video;
+ (Camera *)video
{
    if (!video || video == nil)
    {
        video = [[self alloc] init];
    }
    
    return video;
}

- (void)setVideoOutputDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)videoOutputDelegate {
    videoOutputQueue = pixel_buffer_data_queue_ref();
    if (!captureSession) {
        @try {
            captureSession = [[AVCaptureSession alloc] init];
            [captureSession beginConfiguration];
            if ([captureSession canSetSessionPreset:AVCaptureSessionPreset3840x2160]) {
                [captureSession setSessionPreset:AVCaptureSessionPreset3840x2160];
            }
            
            captureDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
            @try {
                __autoreleasing NSError *error = NULL;
                [captureDevice lockForConfiguration:&error];
                if (error) {
                    NSException* exception = [NSException
                                              exceptionWithName:error.domain
                                              reason:error.localizedDescription
                                              userInfo:@{@"Error Code" : @(error.code)}];
                    @throw exception;
                }
                if ([captureDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
                    [captureDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                if ([captureDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
                    [captureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                [captureDevice setVideoZoomFactor:captureDevice.minAvailableVideoZoomFactor];
            } @catch (NSException *exception) {
                NSLog(@"Error configuring camera:\n\t%@\n\t%@\n\t%lu",
                      exception.name,
                      exception.reason,
                      ((NSNumber *)[exception.userInfo valueForKey:@"Error Code"]).unsignedIntegerValue);
            } @finally {
                [captureDevice unlockForConfiguration];
            }
            
            NSError * error;
            captureInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
            if ([captureSession canAddInput:captureInput])
                [captureSession addInput:captureInput];
            
            captureOutput = [[AVCaptureVideoDataOutput alloc] init];
            [captureOutput setAlwaysDiscardsLateVideoFrames:TRUE];
            [captureOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
            [captureOutput setSampleBufferDelegate:videoOutputDelegate queue:videoOutputQueue];
            
            if ([captureSession canAddOutput:captureOutput])
                [captureSession addOutput:captureOutput];
            
            AVCaptureVideoOrientation __block preferredVideoOrientation = AVCaptureVideoOrientationPortrait;
            UIInterfaceOrientation interfaceOrientation = [[[[UIApplication sharedApplication] windows] firstObject] windowScene].interfaceOrientation;
            if (interfaceOrientation != UIInterfaceOrientationUnknown ) {
                preferredVideoOrientation = (AVCaptureVideoOrientation)interfaceOrientation;
            }
//            previewLayer = (AVCaptureVideoPreviewLayer *)self.cameraView.layer;
//            previewLayer.session = captureSession;
//            previewLayer.connection.videoOrientation = preferredVideoOrientation;
            
            AVCaptureConnection *videoDataCaptureConnection = [[AVCaptureConnection alloc] initWithInputPorts:captureInput.ports output:captureOutput];
            if ([videoDataCaptureConnection isVideoOrientationSupported])
            {
                [captureOutput setAutomaticallyConfiguresOutputBufferDimensions:FALSE];
                [captureOutput setDeliversPreviewSizedOutputBuffers:TRUE];
                [videoDataCaptureConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
                [videoDataCaptureConnection setVideoScaleAndCropFactor:1.0];
            }
            
            if ([captureSession canAddConnection:videoDataCaptureConnection])
                [captureSession addConnection:videoDataCaptureConnection];
            
            [captureSession commitConfiguration];
            
            [captureSession startRunning];
            
        } @catch (NSException *exception) {
            NSLog(@"Camera setup error: %@", exception.description);
        } @finally {
            
        }
    }
}

@end
