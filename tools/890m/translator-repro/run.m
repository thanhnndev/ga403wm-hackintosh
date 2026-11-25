#import <Metal/Metal.h>
#include <stdio.h>
int main(int c, char **v) { @autoreleasepool {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice(); NSError *e = nil;
  for (int i = 1; i < c; i++) {
    NSString *src = [NSString stringWithContentsOfFile:@(v[i]) encoding:NSUTF8StringEncoding error:nil];
    id<MTLLibrary> l = [d newLibraryWithSource:src options:nil error:&e];
    if (!l) { printf("%s compile: %s\n", v[i], e.description.UTF8String); continue; }
    id<MTLComputePipelineState> p = [d newComputePipelineStateWithFunction:[l newFunctionWithName:@"k"] error:&e];
    printf("%-8s %s\n", v[i], p ? "OK" : "FAIL");
  }
}}
