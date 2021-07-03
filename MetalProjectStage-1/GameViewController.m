//
//  GameViewController.m
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/2/21.
//

#import "GameViewController.h"
#import "Renderer.h"

@implementation GameViewController
{
    MTKView *_view;

    Renderer *_renderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _view = (MTKView *)self.view;

    _view.backgroundColor = UIColor.blackColor;
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    _view.sampleCount = 1;
    [_view setPaused:TRUE];
    [_view setEnableSetNeedsDisplay:FALSE];
    [_view setAutoResizeDrawable:FALSE];
    [_view setFramebufferOnly:FALSE];
    [_view setClearColor:MTLClearColorMake(1.0, 1.0, 1.0, 1.0)];
    [_view setDevice:_view.preferredDevice];

    if(!_view.device)
    {
        NSLog(@"Metal is not supported on this device");
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
        return;
    }

    _renderer = [[Renderer alloc] initWithMetalKitView:_view];
}

@end
