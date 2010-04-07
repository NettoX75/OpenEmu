/*
 Copyright (c) 2009, OpenEmu Team
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <OpenGL//CGLMacro.h>

#import "OEGameLayer.h"
#import "GameCore.h"
#import "GameDocument.h"
#import "OECompositionPlugin.h"

#import <IOSurface/IOSurface.h>
#import <OpenGL/CGLIOSurface.h>


@implementation OEGameLayer

@synthesize owner, gameCIImage;
@synthesize docController;
@synthesize rootProxy;

- (BOOL)vSyncEnabled
{
    return vSyncEnabled;
}

- (void)setVSyncEnabled:(BOOL)value
{
    vSyncEnabled = value;
    if(layerContext != nil)
    {
        GLint sync = value;
        CGLSetParameter(layerContext, kCGLCPSwapInterval, &sync);
    }
}

- (NSString *)filterName
{
    return filterName;
}

- (QCComposition *)composition
{
    return [[OECompositionPlugin compositionPluginWithName:filterName] composition];
}

- (void)setFilterName:(NSString *)aName
{
    DLog(@"setting filter name");
    [filterName autorelease];
    filterName = [aName retain];
    
    // since we changed the filtername, if we have a context (ie we are active) lets make a new QCRenderer...
    if(layerContext != NULL)
    {            
        if(filterRenderer && (filterRenderer != nil))
        {
            DLog(@"releasing old filterRenderer");

            [filterRenderer release];
            filterRenderer = nil;
        }    
        
        DLog(@"making new filter renderer");
        
        // this will be responsible for our rendering... weee...    
        QCComposition *compo = [self composition];
        
        if(compo != nil)
        {
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
            filterRenderer = [[QCRenderer alloc] initWithCGLContext:layerContext 
                                                        pixelFormat:CGLGetPixelFormat(layerContext)
                                                         colorSpace:space
                                                        composition:compo];
            CGColorSpaceRelease(space);
        }
        
        if (filterRenderer == nil)
            NSLog(@"Warning: failed to create our filter QCRenderer");
        
        if (![[filterRenderer inputKeys] containsObject:@"OEImageInput"])
            NSLog(@"Warning: invalid Filter composition. Does not contain valid image input key");
        
        if([[filterRenderer outputKeys] containsObject:@"OEMousePositionX"] && [[filterRenderer outputKeys] containsObject:@"OEMousePositionY"])
        {
            DLog(@"filter has mouse output position keys");
            filterHasOutputMousePositionKeys = TRUE;
        }
        else
            filterHasOutputMousePositionKeys = FALSE;
        
    }
}

- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pixelFormat
{
    DLog(@"initing GL context and shaders");
     
    layerContext = [super copyCGLContextForPixelFormat:pixelFormat];
    
    // we need to hold on to this for later.
    CGLRetainContext(layerContext);
    
    [self setVSyncEnabled:vSyncEnabled];

    // our QCRenderer 'filter'
    [self setFilterName:filterName];
	
    return layerContext;
}

- (CGSize)preferredFrameSize
{
    CALayer *superlayer  = [self superlayer];
    NSRect superBounds = NSRectFromCGRect([superlayer bounds]);
    
	//TODO: handle size shit more better
   // NSSize aspect = NSMakeSize(256, 240);
	NSSize aspect;
	
	if(self.gameCIImage == nil)
		aspect = NSMakeSize(320, 240);
	else
		aspect = NSSizeFromCGSize([self.gameCIImage extent].size);
			
    if(superBounds.size.width * (aspect.width * 1.0/aspect.height) > superBounds.size.height * (aspect.width * 1.0/aspect.height))
        return CGSizeMake(superBounds.size.height * (aspect.width * 1.0/aspect.height), superBounds.size.height);
    else
        return CGSizeMake(superBounds.size.width, superBounds.size.width * (aspect.height* 1.0/aspect.width));

}

// FIXME: Maybe this does the same thing as the unused method above?
- (CGFloat)preferredWindowScale
{    
    QCComposition *composition = [self composition];
    NSNumber *scale = [[composition attributes] objectForKey:@"com.openemu.windowScaleFactor"];
    
    if(scale == nil) return 1.0;
    return [scale floatValue];
}

- (BOOL)canDrawInCGLContext:(CGLContextObj)glContext pixelFormat:(CGLPixelFormatObj)pixelFormat forLayerTime:(CFTimeInterval)timeInterval displayTime:(const CVTimeStamp *)timeStamp
{
    // im not sure exactly how the frameFinished stuff works.
    // im tempted to say we should always return yes, 
    // and just only upload a video buffer texture
    // if frameFinished is true, etc.
    
    //return [gameCore frameFinished];
    return YES;
}

- (void)drawInCGLContext:(CGLContextObj)glContext pixelFormat:(CGLPixelFormatObj)pixelFormat forLayerTime:(CFTimeInterval)timeInterval displayTime:(const CVTimeStamp *)timeStamp
{
    // rendering time for QC filters..
    time = [NSDate timeIntervalSinceReferenceDate];
    
    if(startTime == 0)
    {
        startTime = time;
        time = 0;
    }
    else
        time -= startTime;    
    
	// get our IOSurface ID from our helper
	IOSurfaceID surfaceID = [self.rootProxy surfaceID];
	IOSurfaceRef surfaceRef = IOSurfaceLookup(surfaceID); 
	
	// get our IOSurfaceRef from our passed in IOSurfaceID from our background process.
	if(surfaceRef)
	{	
		CFRetain(surfaceRef);

		self.gameCIImage = [CIImage imageWithIOSurface:surfaceRef];
		
		if(filterRenderer != nil)
		{
			// NSPoint mouseLocation = [event locationInWindow];
			NSPoint mouseLocation = [[owner    gameWindow] mouseLocationOutsideOfEventStream];
			mouseLocation.x /= [[[owner gameWindow] contentView] frame].size.width;
			mouseLocation.y /= [[[owner gameWindow] contentView] frame].size.height;
			NSMutableDictionary* arguments = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSValue valueWithPoint:mouseLocation], QCRendererMouseLocationKey, [[owner gameWindow] currentEvent], QCRendererEventKey, nil];
			
			// [filterRenderer setValue:[gameCIImage imageByCroppingToRect:cropRect] forInputKey:@"OEImageInput"];    
			[filterRenderer setValue:self.gameCIImage forInputKey:@"OEImageInput"];
			[filterRenderer renderAtTime:time arguments:arguments];
			
			if(filterHasOutputMousePositionKeys)
			{
				NSPoint mousePoint;
				mousePoint.x = [[filterRenderer valueForOutputKey:@"OEMousePositionX"] floatValue];
				mousePoint.y = [[filterRenderer valueForOutputKey:@"OEMousePositionY"] floatValue];
				
				// TODO: handle setMousePosition.
				//[rootProxy 
				//[gameCore setMousePosition:mousePoint];
			}
		}
		
		// super calls flush for us.
		[super drawInCGLContext:glContext pixelFormat:pixelFormat forLayerTime:timeInterval displayTime:timeStamp];
		
		CFRelease(surfaceRef);
	}	
}

- (id)retain
{
	return [super retain];
}

- (void)dealloc
{
    [self unbind:@"filterName"];
    [self unbind:@"vSyncEnabled"];

    [filterRenderer release];
	
	self.rootProxy = nil;
		
    CGLReleaseContext(layerContext);
    [docController release];
    [super dealloc];
}

- (NSImage *)imageForCurrentFrame
{    
    if([self gameCIImage] == nil) return nil;
        
    NSRect extent = NSRectFromCGRect([[self gameCIImage] extent]);
    int width = extent.size.width; 
    int height = extent.size.height;  
    
	NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCIImage:self.gameCIImage];
	
	
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image addRepresentation:rep];
	[rep release];
    return [image autorelease];
}
@end
