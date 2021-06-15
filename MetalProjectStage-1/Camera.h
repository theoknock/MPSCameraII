//
//  Camera.h
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/15/21.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface Camera : NSObject

+ (Camera *)video;

@property (weak, nonatomic, setter=setVideoOutputDelegate:) id<AVCaptureVideoDataOutputSampleBufferDelegate>videoOutputDelegate;

@end

NS_ASSUME_NONNULL_END
