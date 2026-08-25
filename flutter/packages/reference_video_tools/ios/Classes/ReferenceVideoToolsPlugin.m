#import "ReferenceVideoToolsPlugin.h"

#import <ImageIO/ImageIO.h>
#import <math.h>
#import <ffmpegkit/FFmpegKit.h>
#import <ffmpegkit/FFprobeKit.h>
#import <ffmpegkit/ReturnCode.h>

@implementation ReferenceVideoToolsPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"ai.clawnsole/reference_video_tools"
            binaryMessenger:[registrar messenger]];
  ReferenceVideoToolsPlugin* instance = [[ReferenceVideoToolsPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"convertImageToJpeg"]) {
    NSString* inputPath = call.arguments[@"inputPath"];
    NSString* outputPath = call.arguments[@"outputPath"];
    NSNumber* maxPixels = call.arguments[@"maxPixels"];
    if (![inputPath isKindOfClass:[NSString class]] ||
        ![outputPath isKindOfClass:[NSString class]] ||
        (maxPixels != nil &&
         (![maxPixels isKindOfClass:[NSNumber class]] || maxPixels.longLongValue <= 0))) {
      result([FlutterError errorWithCode:@"invalid_arguments"
                                 message:@"Image conversion paths are missing or the pixel limit is invalid."
                                 details:nil]);
      return;
    }
    [self convertImageAtPath:inputPath
               toJpegAtPath:outputPath
                  maxPixels:maxPixels
                      result:result];
    return;
  }
  if (![call.method isEqualToString:@"execute"]) {
    result(FlutterMethodNotImplemented);
    return;
  }
  NSArray* arguments = call.arguments[@"arguments"];
  NSNumber* probe = call.arguments[@"probe"];
  if (![arguments isKindOfClass:[NSArray class]] || probe == nil) {
    result([FlutterError errorWithCode:@"invalid_arguments"
                               message:@"Media tool arguments are missing."
                               details:nil]);
    return;
  }
  for (id value in arguments) {
    if (![value isKindOfClass:[NSString class]]) {
      result([FlutterError errorWithCode:@"invalid_arguments"
                                 message:@"Media tool arguments must be strings."
                                 details:nil]);
      return;
    }
  }
  if ([probe boolValue]) {
    [FFprobeKit executeWithArgumentsAsync:arguments
                     withCompleteCallback:^(FFprobeSession* session) {
      [self replyWithSession:session result:result];
    }];
  } else {
    [FFmpegKit executeWithArgumentsAsync:arguments
                    withCompleteCallback:^(FFmpegSession* session) {
      [self replyWithSession:session result:result];
    }];
  }
}

- (void)convertImageAtPath:(NSString*)inputPath
              toJpegAtPath:(NSString*)outputPath
                 maxPixels:(NSNumber*)maxPixels
                    result:(FlutterResult)result {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString* message = nil;
    BOOL succeeded = [self renderPrimaryImageAtPath:inputPath
                                      toJpegAtPath:outputPath
                                         maxPixels:maxPixels
                                             error:&message];
    NSDictionary* response = @{
      @"exitCode": succeeded ? @(0) : @(-1),
      @"output": message ?: @"",
    };
    dispatch_async(dispatch_get_main_queue(), ^{
      result(response);
    });
  });
}

- (BOOL)renderPrimaryImageAtPath:(NSString*)inputPath
                    toJpegAtPath:(NSString*)outputPath
                       maxPixels:(NSNumber*)maxPixels
                           error:(NSString**)error {
  NSURL* inputUrl = [NSURL fileURLWithPath:inputPath];
  CGImageSourceRef source = CGImageSourceCreateWithURL(
      (__bridge CFURLRef)inputUrl,
      (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache : @NO});
  if (source == nil || CGImageSourceGetCount(source) == 0) {
    if (source != nil) CFRelease(source);
    if (error != nil) *error = @"The primary reference image could not be decoded.";
    return NO;
  }

  NSDictionary* sourceProperties = CFBridgingRelease(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil));
  NSNumber* pixelWidth = sourceProperties[(id)kCGImagePropertyPixelWidth];
  NSNumber* pixelHeight = sourceProperties[(id)kCGImagePropertyPixelHeight];
  NSInteger width = pixelWidth.integerValue;
  NSInteger height = pixelHeight.integerValue;
  NSInteger maximumDimension = MAX(width, height);
  if (maximumDimension <= 0) {
    CFRelease(source);
    if (error != nil) *error = @"The primary reference image dimensions are invalid.";
    return NO;
  }

  double scale = 1.0;
  if (maxPixels != nil) {
    double sourcePixels = (double)width * (double)height;
    if (sourcePixels > maxPixels.doubleValue) {
      scale = sqrt(maxPixels.doubleValue / sourcePixels);
    }
  }
  NSInteger thumbnailDimension = MAX(1, (NSInteger)floor(maximumDimension * scale));

  // ImageIO resolves the HEIC primary item rather than an auxiliary depth or
  // portrait-matte item. The transform applies orientation and any requested
  // proportional downscale to the complete image; no crop is performed.
  NSDictionary* thumbnailOptions = @{
    (id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (id)kCGImageSourceThumbnailMaxPixelSize : @(thumbnailDimension),
    (id)kCGImageSourceShouldCacheImmediately : @YES,
  };
  CGImageRef primary = CGImageSourceCreateThumbnailAtIndex(
      source, 0, (__bridge CFDictionaryRef)thumbnailOptions);
  CFRelease(source);
  if (primary == nil) {
    if (error != nil) *error = @"The primary reference image could not be decoded.";
    return NO;
  }

  size_t renderedWidth = CGImageGetWidth(primary);
  size_t renderedHeight = CGImageGetHeight(primary);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = colorSpace == nil
      ? nil
      : CGBitmapContextCreate(nil,
                              renderedWidth,
                              renderedHeight,
                              8,
                              renderedWidth * 4,
                              colorSpace,
                              (CGBitmapInfo)kCGImageAlphaPremultipliedLast |
                                  kCGBitmapByteOrder32Big);
  if (colorSpace != nil) CFRelease(colorSpace);
  if (context == nil) {
    CGImageRelease(primary);
    if (error != nil) *error = @"The primary reference image could not be rendered.";
    return NO;
  }
  CGContextSetBlendMode(context, kCGBlendModeCopy);
  CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
  CGContextDrawImage(
      context, CGRectMake(0, 0, renderedWidth, renderedHeight), primary);
  CGImageRelease(primary);
  CGImageRef rendered = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  if (rendered == nil) {
    if (error != nil) *error = @"The primary reference image could not be rendered.";
    return NO;
  }

  NSURL* outputUrl = [NSURL fileURLWithPath:outputPath];
  CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
      (__bridge CFURLRef)outputUrl, CFSTR("public.jpeg"), 1, nil);
  if (destination == nil) {
    CGImageRelease(rendered);
    if (error != nil) *error = @"The normalized reference image could not be saved.";
    return NO;
  }
  NSDictionary* destinationProperties = @{
    (id)kCGImageDestinationLossyCompressionQuality : @(0.94),
    (id)kCGImagePropertyOrientation : @(1),
  };
  CGImageDestinationAddImage(
      destination, rendered, (__bridge CFDictionaryRef)destinationProperties);
  BOOL finalized = CGImageDestinationFinalize(destination);
  CFRelease(destination);
  CGImageRelease(rendered);
  if (!finalized) {
    [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
    if (error != nil) *error = @"The normalized reference image could not be saved.";
    return NO;
  }
  return YES;
}

- (void)replyWithSession:(id<Session>)session result:(FlutterResult)result {
  ReturnCode* returnCode = [session getReturnCode];
  NSDictionary* response = @{
    @"exitCode": returnCode == nil ? @(-1) : @([returnCode getValue]),
    @"output": [session getOutput] ?: @"",
  };
  dispatch_async(dispatch_get_main_queue(), ^{
    result(response);
  });
}

@end
