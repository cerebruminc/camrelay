#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <notify.h>

static NSString *CamRelayProbeArchitecture(void) {
#if defined(__x86_64__)
    return @"x86_64";
#elif defined(__arm64__)
    return @"arm64";
#else
    return @"unknown";
#endif
}

static NSInteger CamRelayProbeClampColor(NSInteger value) {
    return MAX(0, MIN(255, value));
}

static NSString *CamRelayProbePrimaryColor(CVPixelBufferRef pixelBuffer) {
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (width == 0 || height == 0 ||
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
        return nil;
    }

    NSInteger red = 0;
    NSInteger green = 0;
    NSInteger blue = 0;
    BOOL decoded = NO;
    if (pixelFormat == kCVPixelFormatType_32BGRA) {
        const uint8_t *base = CVPixelBufferGetBaseAddress(pixelBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        if (base != NULL && bytesPerRow >= width * 4) {
            const uint8_t *pixel = base + (height / 2) * bytesPerRow + (width / 2) * 4;
            blue = pixel[0];
            green = pixel[1];
            red = pixel[2];
            decoded = YES;
        }
    } else if (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
        pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        const uint8_t *luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        const uint8_t *chroma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        size_t lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        size_t chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        if (luma != NULL && chroma != NULL) {
            size_t x = width / 2;
            size_t y = height / 2;
            NSInteger lumaValue = luma[y * lumaStride + x];
            NSInteger chromaBlue = chroma[(y / 2) * chromaStride + (x / 2) * 2] - 128;
            NSInteger chromaRed = chroma[(y / 2) * chromaStride + (x / 2) * 2 + 1] - 128;
            if (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                NSInteger scaledLuma = MAX(0, lumaValue - 16);
                red = (1192 * scaledLuma + 1634 * chromaRed) / 1024;
                green = (1192 * scaledLuma - 401 * chromaBlue - 833 * chromaRed) / 1024;
                blue = (1192 * scaledLuma + 2066 * chromaBlue) / 1024;
            } else {
                red = lumaValue + (1436 * chromaRed) / 1024;
                green = lumaValue - (352 * chromaBlue + 731 * chromaRed) / 1024;
                blue = lumaValue + (1815 * chromaBlue) / 1024;
            }
            red = CamRelayProbeClampColor(red);
            green = CamRelayProbeClampColor(green);
            blue = CamRelayProbeClampColor(blue);
            decoded = YES;
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    if (!decoded) {
        return nil;
    }
    if (red > green + 40 && red > blue + 40) {
        return @"red";
    }
    if (green > red + 40 && green > blue + 40) {
        return @"green";
    }
    if (blue > red + 40 && blue > green + 40) {
        return @"blue";
    }
    return nil;
}

static BOOL CamRelayProbeFormatSurfacesAreSafe(AVCaptureDeviceFormat *format) {
    if (format == nil) {
        return NO;
    }

    CMVideoDimensions videoDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    CMVideoDimensions photoDimensions = format.supportedMaxPhotoDimensions.firstObject.CMVideoDimensionsValue;
    return [format.mediaType isEqualToString:AVMediaTypeVideo] &&
        videoDimensions.width > 0 &&
        videoDimensions.height > 0 &&
        photoDimensions.width > 0 &&
        photoDimensions.height > 0 &&
        format.videoSupportedFrameRateRanges.count > 0 &&
        format.videoFieldOfView > 0 &&
        !format.isVideoBinned &&
        [format isVideoStabilizationModeSupported:AVCaptureVideoStabilizationModeAuto] &&
        format.videoMaxZoomFactor >= 1.0 &&
        format.videoZoomFactorUpscaleThreshold >= 1.0 &&
        CMTIME_IS_VALID(format.minExposureDuration) &&
        CMTIME_IS_VALID(format.maxExposureDuration) &&
        format.minISO > 0 &&
        format.maxISO >= format.minISO &&
        !format.isGlobalToneMappingSupported &&
        !format.isVideoHDRSupported &&
        format.isHighPhotoQualitySupported &&
        format.isHighestPhotoQualitySupported &&
        format.supportedColorSpaces.count > 0 &&
        format.supportedDepthDataFormats.count == 0 &&
        [format.unsupportedCaptureOutputClasses containsObject:AVCaptureDepthDataOutput.class] &&
        format.secondaryNativeResolutionZoomFactors.count == 0 &&
        !format.isAutoVideoFrameRateSupported &&
        !format.isMultiCamSupported &&
        !format.isSpatialVideoCaptureSupported &&
        !format.isCenterStageSupported &&
        !format.isPortraitEffectSupported &&
        !format.isStudioLightSupported &&
        !format.reactionEffectsSupported &&
        !format.isBackgroundReplacementSupported;
}

@interface CamRelayProbeViewController : UIViewController
    <AVCaptureVideoDataOutputSampleBufferDelegate,
     AVCapturePhotoCaptureDelegate,
     AVCapturePhotoFileDataRepresentationCustomizer,
     AVCaptureFileOutputRecordingDelegate,
     AVCaptureMetadataOutputObjectsDelegate>
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIView *previewView;
@property(nonatomic, strong) UIButton *photoButton;
@property(nonatomic, strong) UIButton *recordButton;
@property(nonatomic, strong) UISegmentedControl *cameraControl;
@property(atomic) NSUInteger cameraIndex;
@property(nonatomic, strong) AVCaptureSession *captureSession;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property(nonatomic, strong) AVCaptureMovieFileOutput *movieOutput;
@property(nonatomic, strong) AVCaptureMetadataOutput *metadataOutput;
@property(nonatomic) NSUInteger frameCount;
@property(nonatomic) NSUInteger photoCount;
@property(nonatomic) NSUInteger movieCount;
@property(nonatomic) NSUInteger lastMovieBytes;
@property(nonatomic, strong) NSMutableSet<NSString *> *observedColors;
@property(nonatomic, copy) NSString *lastObservedColor;
@property(nonatomic) NSUInteger colorTransitionCount;
@property(nonatomic) BOOL compatibilityConfigured;
@property(nonatomic) CMVideoDimensions activeVideoDimensions;
@property(nonatomic) BOOL videoDimensionsValidated;
@property(nonatomic) BOOL automaticPhotoRequested;
@property(nonatomic) BOOL automaticRecordingStarted;
@property(nonatomic) BOOL automaticRecordingStopped;
- (void)handleValidationAction:(NSString *)action;
@end

@implementation CamRelayProbeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.observedColors = [NSMutableSet set];

    self.cameraControl = [[UISegmentedControl alloc] initWithItems:@[@"Front", @"Back"]];
    self.cameraControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraControl.selectedSegmentIndex = 0;
    self.cameraControl.accessibilityIdentifier = @"camera-position";
    [self.cameraControl addTarget:self action:@selector(changeCamera) forControlEvents:UIControlEventValueChanged];

    self.previewView = [[UIView alloc] initWithFrame:CGRectZero];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewView.backgroundColor = UIColor.blackColor;
    self.previewView.accessibilityIdentifier = @"camera-preview";

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightMedium];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.accessibilityIdentifier = @"camera-status";
    self.statusLabel.text = @"Checking camera…";

    self.photoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.photoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.photoButton setTitle:@"Capture Photo" forState:UIControlStateNormal];
    [self.photoButton addTarget:self action:@selector(capturePhoto) forControlEvents:UIControlEventTouchUpInside];
    self.photoButton.accessibilityIdentifier = @"capture-photo";
    self.photoButton.enabled = NO;

    self.recordButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.recordButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.recordButton setTitle:@"Start Recording" forState:UIControlStateNormal];
    [self.recordButton addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchUpInside];
    self.recordButton.accessibilityIdentifier = @"toggle-recording";
    self.recordButton.enabled = NO;

    [self.view addSubview:self.previewView];
    [self.view addSubview:self.cameraControl];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.photoButton];
    [self.view addSubview:self.recordButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.cameraControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.cameraControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.cameraControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.previewView.topAnchor constraintEqualToAnchor:self.cameraControl.bottomAnchor constant:16],
        [self.previewView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.previewView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.previewView.heightAnchor constraintEqualToAnchor:self.previewView.widthAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.previewView.bottomAnchor constant:24],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.photoButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:18],
        [self.photoButton.trailingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-10],
        [self.recordButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:18],
        [self.recordButton.leadingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:10],
    ]];

    [self startCamera];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.previewView.bounds;
}

- (void)startCamera {
    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
        mediaType:AVMediaTypeVideo
        position:AVCaptureDevicePositionFront];
    AVCaptureDevice *device = discovery.devices.firstObject;
    if (device == nil) {
        [self updateStatus:[NSString stringWithFormat:
            @"Arch: %@\nNo camera found",
            CamRelayProbeArchitecture()]];
        return;
    }
    BOOL uniqueIDLookupMatches = [AVCaptureDevice deviceWithUniqueID:device.uniqueID] == device;

    NSError *inputError = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&inputError];
    if (input == nil) {
        [self updateStatus:[NSString stringWithFormat:@"Camera input failed\n%@", inputError.localizedDescription]];
        return;
    }

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.alwaysDiscardsLateVideoFrames =
        ![NSProcessInfo.processInfo.arguments containsObject:@"--keep-late-video-frames"];
    dispatch_queue_t queue = dispatch_queue_create("org.camrelay.probe.frames", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:queue];

    AVCapturePhotoOutput *photoOutput = [[AVCapturePhotoOutput alloc] init];
    AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    AVCaptureMetadataOutput *metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    dispatch_queue_t metadataQueue = dispatch_queue_create(
        "org.camrelay.probe.metadata",
        DISPATCH_QUEUE_SERIAL
    );
    [metadataOutput setMetadataObjectsDelegate:self queue:metadataQueue];

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];
    if (![session canAddInput:input] ||
        ![session canAddOutput:output] ||
        ![session canAddOutput:photoOutput] ||
        ![session canAddOutput:movieOutput] ||
        ![session canAddOutput:metadataOutput]) {
        [session commitConfiguration];
        [self updateStatus:@"Camera session rejected input or output"];
        return;
    }
    [session addInput:input];
    [session addOutput:output];
    [session addOutput:photoOutput];
    [session addOutput:movieOutput];
    [session addOutput:metadataOutput];
    output.videoSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    };
    if (@available(iOS 16.0, *)) {
        photoOutput.maxPhotoDimensions =
            device.activeFormat.supportedMaxPhotoDimensions.lastObject.CMVideoDimensionsValue;
    }
    if ([metadataOutput.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
        metadataOutput.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
    }
    [session commitConfiguration];
    self.captureSession = session;
    self.photoOutput = photoOutput;
    self.movieOutput = movieOutput;
    self.metadataOutput = metadataOutput;

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.previewView.layer addSublayer:self.previewLayer];

    AVCaptureDeviceFormat *activeFormat = device.activeFormat;
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription);
    BOOL formatSurfacesSafe = CamRelayProbeFormatSurfacesAreSafe(activeFormat);
    BOOL configured = device.formats.count > 0 &&
        formatSurfacesSafe &&
        uniqueIDLookupMatches &&
        input.ports.count > 0 &&
        session.inputs.count > 0 &&
        session.outputs.count == 4 &&
        session.connections.count >= 4 &&
        output.connections.count == 1 &&
        photoOutput.connections.count == 1 &&
        movieOutput.connections.count == 1 &&
        self.previewLayer.connection != nil;
    NSLog(@"[CamRelayProbe] compatibility formats=%lu formatSurfaces=%@ uniqueIDLookup=%@ ports=%lu inputs=%lu outputs=%lu connections=%lu configured=%@ dimensions=%dx%d",
        (unsigned long)device.formats.count,
        formatSurfacesSafe ? @"safe" : @"unsafe",
        uniqueIDLookupMatches ? @"matches" : @"mismatch",
        (unsigned long)input.ports.count,
        (unsigned long)session.inputs.count,
        (unsigned long)session.outputs.count,
        (unsigned long)session.connections.count,
        configured ? @"yes" : @"no",
        dimensions.width,
        dimensions.height);

    self.photoButton.enabled = configured;
    self.recordButton.enabled = configured;
    self.compatibilityConfigured = configured;
    self.activeVideoDimensions = dimensions;

    [self updateStatus:[NSString stringWithFormat:@"Camera: %@\n%@\nWaiting for frames…",
        device.localizedName,
        configured ? @"Common surfaces configured" : @"Compatibility configuration incomplete"]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [session startRunning];
    });
}

- (void)capturePhoto {
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettingsWithFormat:@{
        AVVideoCodecKey: AVVideoCodecTypeJPEG
    }];
    [self.photoOutput capturePhotoWithSettings:settings delegate:self];
}

- (NSString *)cameraName {
    return @[@"front", @"back"][MIN(self.cameraIndex, 1)];
}

- (void)handleValidationAction:(NSString *)action {
    NSUInteger index = [@[@"front", @"back"] indexOfObject:action];
    if (index != NSNotFound) {
        self.cameraControl.selectedSegmentIndex = (NSInteger)index;
        [self changeCamera];
    } else if ([action isEqualToString:@"capture"] && self.photoButton.enabled) {
        [self capturePhoto];
    } else if ([action isEqualToString:@"record"] && self.recordButton.enabled) {
        [self toggleRecording];
    }
}

- (void)changeCamera {
    self.cameraIndex = (NSUInteger)self.cameraControl.selectedSegmentIndex;
    AVCaptureDevicePosition position = self.cameraIndex == 0 ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    AVCaptureDeviceInput *existing = (AVCaptureDeviceInput *)self.captureSession.inputs.firstObject;
    if (existing.device.position != position) {
        AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
            mediaType:AVMediaTypeVideo position:position];
        AVCaptureDevice *device = discovery.devices.firstObject;
        NSError *error = nil;
        AVCaptureDeviceInput *input = device == nil ? nil : [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
        if (input == nil) {
            [self updateStatus:error.localizedDescription ?: @"Requested camera is unavailable"];
            return;
        }
        [self.captureSession beginConfiguration];
        if (existing != nil) { [self.captureSession removeInput:existing]; }
        if ([self.captureSession canAddInput:input]) {
            [self.captureSession addInput:input];
        } else if (existing != nil) {
            [self.captureSession addInput:existing];
        }
        // Exercise replacing an output as part of a normal camera reconfiguration.
        [self.captureSession removeOutput:self.photoOutput];
        self.photoOutput = [[AVCapturePhotoOutput alloc] init];
        [self.captureSession addOutput:self.photoOutput];
        [self.captureSession commitConfiguration];
        AVCaptureInputPort *photoPort = self.photoOutput.connections.firstObject.inputPorts.firstObject;
        BOOL connected = photoPort.input == self.captureSession.inputs.firstObject &&
            self.captureSession.outputs.count == 4 && self.captureSession.connections.count == 5;
        NSLog(@"[CamRelayProbe] reconfiguration connections=%lu ports=%@",
            (unsigned long)self.captureSession.connections.count, connected ? @"valid" : @"invalid");
    }
    NSLog(@"[CamRelayProbe] camera=%@", self.cameraName);
}

- (void)toggleRecording {
    if (self.movieOutput.isRecording) {
        [self.movieOutput stopRecording];
        return;
    }
    NSString *fileName = [NSString stringWithFormat:@"CamRelayProbe-%@.mov", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    [self.movieOutput startRecordingToOutputFileURL:url recordingDelegate:self];
    [self.recordButton setTitle:@"Stop Recording" forState:UIControlStateNormal];
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
    fromConnection:(AVCaptureConnection *)connection {
    // Exercise late-frame delivery without making normal probe runs slower.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--slow-video-callback"]) {
        [NSThread sleepForTimeInterval:0.5];
        return;
    }
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer == NULL) {
        return;
    }

    self.frameCount += 1;
    NSString *primaryColor = CamRelayProbePrimaryColor(pixelBuffer);
    if (primaryColor != nil) {
        [self.observedColors addObject:primaryColor];
        if (self.lastObservedColor != nil &&
            ![self.lastObservedColor isEqualToString:primaryColor]) {
            self.colorTransitionCount += 1;
            NSLog(
                @"[CamRelayProbe] color=%@ observed=%lu transitions=%lu",
                primaryColor,
                (unsigned long)self.observedColors.count,
                (unsigned long)self.colorTransitionCount
            );
        }
        self.lastObservedColor = primaryColor;
    }
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (!self.videoDimensionsValidated) {
        self.videoDimensionsValidated = YES;
        BOOL dimensionsMatch = width == (size_t)self.activeVideoDimensions.width &&
            height == (size_t)self.activeVideoDimensions.height;
        if (!dimensionsMatch) {
            self.compatibilityConfigured = NO;
        }
        NSLog(
            @"[CamRelayProbe] video dimensions format=%dx%d frame=%zux%zu match=%@",
            self.activeVideoDimensions.width,
            self.activeVideoDimensions.height,
            width,
            height,
            dimensionsMatch ? @"yes" : @"no"
        );
    }
    NSUInteger count = self.frameCount;
    NSUInteger photos = self.photoCount;
    NSUInteger movies = self.movieCount;
    NSUInteger movieBytes = self.lastMovieBytes;
    NSUInteger colors = self.observedColors.count;
    NSUInteger transitions = self.colorTransitionCount;
    double presentationTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
    if (count >= 5 && !self.automaticPhotoRequested) {
        self.automaticPhotoRequested = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self capturePhoto];
        });
    }
    if (count >= 10 && !self.automaticRecordingStarted) {
        self.automaticRecordingStarted = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self toggleRecording];
        });
    }
    if (count >= 40 && self.automaticRecordingStarted && !self.automaticRecordingStopped) {
        self.automaticRecordingStopped = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self toggleRecording];
        });
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:
            @"Arch: %@  Surfaces: %@\n"
             "Frames: %lu  Photos: %lu  Movies: %lu\n"
             "%zux%zu  Preview: %@\n"
             "Colors: %lu  Transitions: %lu  Movie: %lu B",
            CamRelayProbeArchitecture(),
            self.compatibilityConfigured ? @"ready" : @"failed",
            (unsigned long)count,
            (unsigned long)photos,
            (unsigned long)movies,
            width,
            height,
            self.previewLayer.isPreviewing ? @"active" : @"inactive",
            (unsigned long)colors,
            (unsigned long)transitions,
            (unsigned long)movieBytes];
        if (count == 1 || count % 15 == 0) {
            NSLog(
                @"[CamRelayProbe] frame=%lu size=%zux%zu colors=%lu transitions=%lu camera=%@ pts=%.3f color=%@",
                (unsigned long)count,
                width,
                height,
                (unsigned long)colors,
                (unsigned long)transitions,
                self.cameraName,
                presentationTime,
                primaryColor ?: @"other"
            );
        }
    });
}

- (NSDictionary *)replacementMetadataForPhoto:(AVCapturePhoto *)photo {
    return @{(__bridge NSString *)kCGImagePropertyExifDictionary:
        @{(__bridge NSString *)kCGImagePropertyExifUserComment: @"capture-validation"}};
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
    error:(NSError *)error {
    NSData *data = photo.fileDataRepresentation;
    NSDictionary *exif = photo.metadata[(__bridge NSString *)kCGImagePropertyExifDictionary];
    if ([exif[(__bridge NSString *)kCGImagePropertyExifPixelXDimension] intValue] != photo.resolvedSettings.photoDimensions.width ||
        [exif[(__bridge NSString *)kCGImagePropertyExifPixelYDimension] intValue] != photo.resolvedSettings.photoDimensions.height) {
        NSLog(@"[CamRelayProbe] photo metadata dimensions failed");
        return;
    }
    NSData *customized = [photo fileDataRepresentationWithCustomizer:self];
    CGImageSourceRef source = customized != nil
        ? CGImageSourceCreateWithData((__bridge CFDataRef)customized, NULL) : NULL;
    NSDictionary *properties = source != NULL
        ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
    if (source != NULL) { CFRelease(source); }
    NSString *comment = properties[(__bridge NSString *)kCGImagePropertyExifDictionary]
        [(__bridge NSString *)kCGImagePropertyExifUserComment];
    if (![comment isEqualToString:@"capture-validation"]) {
        NSLog(@"[CamRelayProbe] photo metadata customization failed");
        return;
    }
    if (error != nil || data.length == 0) {
        NSLog(@"[CamRelayProbe] photo failed: %@", error.localizedDescription ?: @"no image data");
        return;
    }
    self.photoCount += 1;
    NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CamRelayProbe-photo-%lu.jpg", (unsigned long)self.photoCount]]];
    NSError *writeError = nil;
    if (![data writeToURL:fileURL options:NSDataWritingAtomic error:&writeError]) {
        NSLog(@"[CamRelayProbe] photo save failed: %@", writeError.localizedDescription);
        return;
    }
    UIImage *image = [UIImage imageWithData:data];
    uint8_t pixel[4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (context != NULL && image.CGImage != NULL) {
        CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    }
    if (context != NULL) { CGContextRelease(context); }
    CGColorSpaceRelease(colorSpace);
    NSLog(@"[CamRelayProbe] photo=%lu bytes=%lu dimensions=%dx%d camera=%@ rgb=%u,%u,%u metadata=YES file=%@",
        (unsigned long)self.photoCount,
        (unsigned long)data.length,
        photo.resolvedSettings.photoDimensions.width,
        photo.resolvedSettings.photoDimensions.height,
        self.cameraName, pixel[0], pixel[1], pixel[2], fileURL.path);
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects
    fromConnection:(AVCaptureConnection *)connection {
    for (AVMetadataMachineReadableCodeObject *object in metadataObjects) {
        NSLog(@"[CamRelayProbe] metadata type=%@ value=%@", object.type, object.stringValue);
    }
}

- (void)captureOutput:(AVCaptureFileOutput *)output
    didStartRecordingToOutputFileAtURL:(NSURL *)fileURL
    fromConnections:(NSArray<AVCaptureConnection *> *)connections {
    NSLog(@"[CamRelayProbe] recording started connections=%lu", (unsigned long)connections.count);
}

- (void)captureOutput:(AVCaptureFileOutput *)output
    didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
    fromConnections:(NSArray<AVCaptureConnection *> *)connections
    error:(NSError *)error {
    NSNumber *fileSize = nil;
    [outputFileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
    NSLog(@"[CamRelayProbe] recording finished bytes=%@ error=%@", fileSize, error.localizedDescription);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (error == nil && fileSize.unsignedIntegerValue > 0) {
            self.movieCount += 1;
            self.lastMovieBytes = fileSize.unsignedIntegerValue;
        }
        [self.recordButton setTitle:@"Start Recording" forState:UIControlStateNormal];
    });
}

- (void)updateStatus:(NSString *)status {
    NSLog(@"[CamRelayProbe] status=%@", status);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = status;
    });
}

@end

@interface CamRelayProbeAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *validationTokens;
@end

@implementation CamRelayProbeAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[CamRelayProbeViewController alloc] init];
    [self.window makeKeyAndVisible];
    // Opt-in test controls use the same screen actions as the buttons. The
    // validation app still discovers and captures through AVFoundation only.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--validation-controls"]) {
        self.validationTokens = [NSMutableArray array];
        for (NSString *action in @[@"front", @"back", @"capture", @"record"]) {
            NSString *name = [@"org.camrelay.probe.validation." stringByAppendingString:action];
            int token;
            __weak CamRelayProbeAppDelegate *weakSelf = self;
            uint32_t status = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int value) {
                CamRelayProbeViewController *controller = (CamRelayProbeViewController *)weakSelf.window.rootViewController;
                [controller handleValidationAction:action];
            });
            if (status == NOTIFY_STATUS_OK) { [self.validationTokens addObject:@(token)]; }
        }
    }
    return YES;
}

- (void)dealloc {
    for (NSNumber *token in self.validationTokens) { notify_cancel(token.intValue); }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(CamRelayProbeAppDelegate.class));
    }
}
