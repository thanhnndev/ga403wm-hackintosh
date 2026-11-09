#!/bin/sh
# builds inuse_test next to this script
cd "$(dirname "$0")" && xcrun clang -fobjc-arc -O1 -o inuse_test inuse_test.m -framework Cocoa -framework QuartzCore -framework IOSurface -framework Metal
