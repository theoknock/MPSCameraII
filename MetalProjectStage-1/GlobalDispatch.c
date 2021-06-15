//
//  GlobalDispatch.c
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/15/21.
//

#include <stdio.h>

#include "GlobalDispatch.h"

dispatch_queue_t pixel_buffer_data_queue;

dispatch_queue_t (^pixel_buffer_data_queue_ref)(void) = ^ dispatch_queue_t (void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!pixel_buffer_data_queue || pixel_buffer_data_queue == NULL) {
            pixel_buffer_data_queue = dispatch_queue_create_with_target("CVPixelBufferDispatchQueue", DISPATCH_QUEUE_SERIAL, dispatch_get_main_queue());
        }
    });

    return pixel_buffer_data_queue;
};
