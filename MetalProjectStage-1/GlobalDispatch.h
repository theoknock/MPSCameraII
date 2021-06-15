//
//  GlobalDispatch.h
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/15/21.
//

#ifndef GlobalDispatch_h
#define GlobalDispatch_h

#include <stdio.h>
#include <dispatch/dispatch.h>

extern dispatch_queue_t pixel_buffer_data_queue;
extern dispatch_queue_t (^pixel_buffer_data_queue_ref)(void);

#endif /* GlobalDispatch_h */
