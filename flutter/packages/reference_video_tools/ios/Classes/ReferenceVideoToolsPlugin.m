#import "ReferenceVideoToolsPlugin.h"

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
