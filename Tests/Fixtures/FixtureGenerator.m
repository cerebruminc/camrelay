#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

static CVPixelBufferRef CreatePixelBuffer(CVPixelBufferPoolRef pool, uint8_t red, uint8_t green, uint8_t blue) {
    CVPixelBufferRef pixelBuffer = NULL;
    if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) != kCVReturnSuccess) {
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    uint8_t *base = CVPixelBufferGetBaseAddress(pixelBuffer);
    for (size_t row = 0; row < height; row += 1) {
        uint8_t *pixel = base + row * bytesPerRow;
        for (size_t column = 0; column < width; column += 1) {
            pixel[0] = blue;
            pixel[1] = green;
            pixel[2] = red;
            pixel[3] = 255;
            pixel += 4;
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return pixelBuffer;
}

static BOOL WriteRedPNG(NSURL *url) {
    const size_t width = 320;
    const size_t height = 240;
    const size_t bytesPerRow = width * 4;
    uint8_t *bytes = calloc(height, bytesPerRow);
    if (bytes == NULL) {
        return NO;
    }
    for (size_t pixelIndex = 0; pixelIndex < width * height; pixelIndex += 1) {
        bytes[pixelIndex * 4 + 2] = 255;
        bytes[pixelIndex * 4 + 3] = 255;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        bytes,
        width,
        height,
        8,
        bytesPerRow,
        colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
    );
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)url,
        CFSTR("public.png"),
        1,
        NULL
    );
    BOOL success = destination != NULL;
    if (destination != NULL) {
        CGImageDestinationAddImage(destination, image, NULL);
        success = CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CGImageRelease(image);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    free(bytes);
    return success;
}

static BOOL WriteColorVideo(NSURL *url, NSError **error) {
    const NSInteger width = 320;
    const NSInteger height = 240;
    const int32_t framesPerSecond = 15;
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:error];
    if (writer == nil) {
        return NO;
    }
    AVAssetWriterInput *input = [AVAssetWriterInput
        assetWriterInputWithMediaType:AVMediaTypeVideo
        outputSettings:@{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(width),
            AVVideoHeightKey: @(height),
        }];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (NSString *)kCVPixelBufferWidthKey: @(width),
            (NSString *)kCVPixelBufferHeightKey: @(height),
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        }];
    if (![writer canAddInput:input]) {
        return NO;
    }
    [writer addInput:input];
    if (![writer startWriting]) {
        if (error != NULL) {
            *error = writer.error;
        }
        return NO;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];

    if (adaptor.pixelBufferPool == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"CamRelayFixtureGenerator" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"AVAssetWriter did not create a pixel buffer pool."
            }];
        }
        return NO;
    }

    for (int64_t frame = 0; frame < 45; frame += 1) {
        while (!input.readyForMoreMediaData) {
            usleep(1000);
        }
        uint8_t red = frame < 15 ? 255 : 0;
        uint8_t green = frame >= 15 && frame < 30 ? 255 : 0;
        uint8_t blue = frame >= 30 ? 255 : 0;
        CVPixelBufferRef pixelBuffer = CreatePixelBuffer(adaptor.pixelBufferPool, red, green, blue);
        if (pixelBuffer == NULL || ![adaptor appendPixelBuffer:pixelBuffer withPresentationTime:CMTimeMake(frame, framesPerSecond)]) {
            if (pixelBuffer != NULL) {
                CVPixelBufferRelease(pixelBuffer);
            }
            if (error != NULL) {
                *error = writer.error ?: [NSError errorWithDomain:@"CamRelayFixtureGenerator" code:2 userInfo:@{
                    NSLocalizedDescriptionKey: @"AVAssetWriter rejected a generated frame."
                }];
            }
            return NO;
        }
        CVPixelBufferRelease(pixelBuffer);
    }

    [input markAsFinished];
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{
        dispatch_semaphore_signal(finished);
    }];
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) {
        if (error != NULL) {
            *error = writer.error;
        }
        return NO;
    }
    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: FixtureGenerator <output-directory>\n");
            return 2;
        }
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        NSError *directoryError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
            fprintf(stderr, "%s\n", directoryError.localizedDescription.UTF8String);
            return 1;
        }

        NSURL *directoryURL = [NSURL fileURLWithPath:directory isDirectory:YES];
        if (!WriteRedPNG([directoryURL URLByAppendingPathComponent:@"red.png"])) {
            fprintf(stderr, "could not create red.png\n");
            return 1;
        }
        NSError *videoError = nil;
        if (!WriteColorVideo([directoryURL URLByAppendingPathComponent:@"colors.mp4"], &videoError)) {
            fprintf(stderr, "%s\n", (videoError.localizedDescription ?: @"could not create colors.mp4").UTF8String);
            return 1;
        }
        printf("%s\n", directory.UTF8String);
        return 0;
    }
}
