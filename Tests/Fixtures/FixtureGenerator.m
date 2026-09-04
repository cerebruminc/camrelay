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

static BOOL WritePNG(NSURL *url, BOOL checkerboard) {
    const size_t width = checkerboard ? 480 : 320;
    const size_t height = checkerboard ? 640 : 240;
    const size_t bytesPerRow = width * 4;
    uint8_t *bytes = calloc(height, bytesPerRow);
    if (bytes == NULL) {
        return NO;
    }
    for (size_t y = 0; y < height; y += 1) {
        for (size_t x = 0; x < width; x += 1) {
            uint8_t *pixel = bytes + y * bytesPerRow + x * 4;
            uint8_t shade = ((x / 80 + y / 80) % 2 == 0) ? 255 : 0;
            pixel[0] = checkerboard ? shade : 0;
            pixel[1] = checkerboard ? shade : 0;
            pixel[2] = checkerboard ? shade : 255;
            pixel[3] = 255;
        }
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

static void DrawMovingShapes(CVPixelBufferRef buffer, double progress) {
    CVPixelBufferLockBaseAddress(buffer, 0);
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
    // Periodic paths return to their starting positions at the loop boundary.
    double angle = progress * 2 * M_PI;
    double circleX = width * (0.5 + 0.3 * sin(angle));
    double circleY = height * 0.32;
    double radius = height * 0.13;
    double squareX = width * (0.5 + 0.3 * cos(angle));
    double squareY = height * 0.72;
    double halfSide = height * 0.12;
    for (size_t y = 0; y < height; y += 1) {
        for (size_t x = 0; x < width; x += 1) {
            uint8_t *pixel = base + y * stride + x * 4;
            double dx = x - circleX, dy = y - circleY;
            BOOL circle = dx * dx + dy * dy < radius * radius;
            BOOL square = fabs(x - squareX) < halfSide && fabs(y - squareY) < halfSide;
            pixel[0] = circle ? 40 : square ? 80 : 40;
            pixel[1] = circle ? 80 : square ? 230 : 24;
            pixel[2] = circle ? 240 : square ? 40 : 16;
            pixel[3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
}

static BOOL WriteVideo(NSURL *url, NSInteger width, NSInteger height, int32_t framesPerSecond, NSInteger colorOffset, BOOL movingShapes, NSError **error) {
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

    for (int64_t frame = 0; frame < framesPerSecond * 3; frame += 1) {
        while (!input.readyForMoreMediaData) {
            if (writer.status != AVAssetWriterStatusWriting) {
                if (error != NULL) { *error = writer.error; }
                return NO;
            }
            usleep(1000);
        }
        NSInteger color = (frame / framesPerSecond + colorOffset) % 3;
        uint8_t red = color == 0 ? 255 : 0;
        uint8_t green = color == 1 ? 255 : 0;
        uint8_t blue = color == 2 ? 255 : 0;
        CVPixelBufferRef pixelBuffer = CreatePixelBuffer(adaptor.pixelBufferPool, red, green, blue);
        if (pixelBuffer != NULL && movingShapes) {
            DrawMovingShapes(pixelBuffer, (double)frame / (framesPerSecond * 3));
        }
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
        if (!WritePNG([directoryURL URLByAppendingPathComponent:@"red.png"], NO) ||
            !WritePNG([directoryURL URLByAppendingPathComponent:@"checkerboard.png"], YES)) {
            fprintf(stderr, "could not create PNG fixtures\n");
            return 1;
        }
        NSError *videoError = nil;
        NSArray<NSDictionary *> *videos = @[
            @{@"name": @"colors.mp4", @"width": @320, @"height": @240, @"fps": @15, @"offset": @0},
            @{@"name": @"moving-shapes.mp4", @"width": @1280, @"height": @720, @"fps": @24, @"motion": @YES},
            @{@"name": @"colors-720p.mp4", @"width": @1280, @"height": @720, @"fps": @24, @"offset": @1},
            @{@"name": @"colors-portrait.mp4", @"width": @480, @"height": @640, @"fps": @12, @"offset": @2},
            @{@"name": @"colors-1080p.mp4", @"width": @1920, @"height": @1080, @"fps": @30, @"offset": @0},
        ];
        for (NSDictionary *video in videos) {
            if (!WriteVideo(
                [directoryURL URLByAppendingPathComponent:video[@"name"]],
                [video[@"width"] integerValue], [video[@"height"] integerValue],
                [video[@"fps"] intValue], [video[@"offset"] integerValue], [video[@"motion"] boolValue], &videoError
            )) {
                fprintf(stderr, "%s: %s\n", [video[@"name"] UTF8String],
                    (videoError.localizedDescription ?: @"could not create video").UTF8String);
                return 1;
            }
        }
        printf("%s\n", directory.UTF8String);
        return 0;
    }
}
