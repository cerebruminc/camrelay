#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <arpa/inet.h>
#import <math.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <sys/socket.h>
#import <unistd.h>

static const void *CamRelayDevicePositionKey = &CamRelayDevicePositionKey;
static const void *CamRelayDeviceActiveFormatKey = &CamRelayDeviceActiveFormatKey;
static const void *CamRelayDeviceFocusModeKey = &CamRelayDeviceFocusModeKey;
static const void *CamRelayDeviceFocusPointKey = &CamRelayDeviceFocusPointKey;
static const void *CamRelayDeviceExposureModeKey = &CamRelayDeviceExposureModeKey;
static const void *CamRelayDeviceExposurePointKey = &CamRelayDeviceExposurePointKey;
static const void *CamRelayDeviceWhiteBalanceModeKey = &CamRelayDeviceWhiteBalanceModeKey;
static const void *CamRelayDeviceZoomKey = &CamRelayDeviceZoomKey;
static const void *CamRelayDeviceMinFrameDurationKey = &CamRelayDeviceMinFrameDurationKey;
static const void *CamRelayDeviceMaxFrameDurationKey = &CamRelayDeviceMaxFrameDurationKey;
static const void *CamRelayDiscoveryMediaTypeKey = &CamRelayDiscoveryMediaTypeKey;
static const void *CamRelayDiscoveryPositionKey = &CamRelayDiscoveryPositionKey;
static const void *CamRelayDiscoveryDeviceTypesKey = &CamRelayDiscoveryDeviceTypesKey;
static const void *CamRelayInputDeviceKey = &CamRelayInputDeviceKey;
static const void *CamRelayInputPortKey = &CamRelayInputPortKey;
static const void *CamRelayPortInputKey = &CamRelayPortInputKey;
static const void *CamRelayPortEnabledKey = &CamRelayPortEnabledKey;
static const void *CamRelaySyntheticInputsKey = &CamRelaySyntheticInputsKey;
static const void *CamRelaySyntheticOutputsKey = &CamRelaySyntheticOutputsKey;
static const void *CamRelaySyntheticConnectionsKey = &CamRelaySyntheticConnectionsKey;
static const void *CamRelayPreviewLayersKey = &CamRelayPreviewLayersKey;
static const void *CamRelayEmitterKey = &CamRelayEmitterKey;
static const void *CamRelayRunningKey = &CamRelayRunningKey;
static const void *CamRelaySessionPresetKey = &CamRelaySessionPresetKey;
static const void *CamRelayCommittingConfigurationKey = &CamRelayCommittingConfigurationKey;
static const void *CamRelayOutputSessionKey = &CamRelayOutputSessionKey;
static const void *CamRelayOutputConnectionKey = &CamRelayOutputConnectionKey;
static const void *CamRelayConnectionInputPortsKey = &CamRelayConnectionInputPortsKey;
static const void *CamRelayConnectionOutputKey = &CamRelayConnectionOutputKey;
static const void *CamRelayConnectionPreviewLayerKey = &CamRelayConnectionPreviewLayerKey;
static const void *CamRelayConnectionEnabledKey = &CamRelayConnectionEnabledKey;
static const void *CamRelayConnectionMirroredKey = &CamRelayConnectionMirroredKey;
static const void *CamRelayConnectionAutoMirrorKey = &CamRelayConnectionAutoMirrorKey;
static const void *CamRelayConnectionOrientationKey = &CamRelayConnectionOrientationKey;
static const void *CamRelayConnectionRotationKey = &CamRelayConnectionRotationKey;
static const void *CamRelayConnectionStabilizationKey = &CamRelayConnectionStabilizationKey;
static const void *CamRelayPreviewConnectionKey = &CamRelayPreviewConnectionKey;
static const void *CamRelayPreviewSessionKey = &CamRelayPreviewSessionKey;
static const void *CamRelayPreviewDisplayLayerKey = &CamRelayPreviewDisplayLayerKey;
static const void *CamRelayLatestSampleBufferKey = &CamRelayLatestSampleBufferKey;
static const void *CamRelayPhotoRequestsKey = &CamRelayPhotoRequestsKey;
static const void *CamRelayPhotoPixelBufferKey = &CamRelayPhotoPixelBufferKey;
static const void *CamRelayPhotoDataKey = &CamRelayPhotoDataKey;
static const void *CamRelayPhotoResolvedSettingsKey = &CamRelayPhotoResolvedSettingsKey;
static const void *CamRelayPhotoTimestampKey = &CamRelayPhotoTimestampKey;
static const void *CamRelayPhotoCGImageKey = &CamRelayPhotoCGImageKey;
static const void *CamRelayResolvedUniqueIDKey = &CamRelayResolvedUniqueIDKey;
static const void *CamRelayResolvedDimensionsKey = &CamRelayResolvedDimensionsKey;
static const void *CamRelayPhotoHighResolutionKey = &CamRelayPhotoHighResolutionKey;
static const void *CamRelayPhotoQualityKey = &CamRelayPhotoQualityKey;
static const void *CamRelayMetadataTypesKey = &CamRelayMetadataTypesKey;
static const void *CamRelayMetadataStringKey = &CamRelayMetadataStringKey;
static const void *CamRelayMetadataBoundsKey = &CamRelayMetadataBoundsKey;
static const void *CamRelayMetadataTimeKey = &CamRelayMetadataTimeKey;
static const void *CamRelayMetadataCornersKey = &CamRelayMetadataCornersKey;
static const void *CamRelayMovieRecorderKey = &CamRelayMovieRecorderKey;
static const void *CamRelayMovieOutputSettingsKey = &CamRelayMovieOutputSettingsKey;
static NSString *const CamRelayConstructingCaptureOutputKey = @"CamRelayConstructingCaptureOutput";
static const uint8_t CamRelayFrameClientRole = 0x46; // F
static const uint8_t CamRelayControlClientRole = 0x43; // C
static atomic_bool CamRelayRuntimeActive = false;

static BOOL CamRelayIsConstructingCaptureOutput(void) {
    return [NSThread.currentThread.threadDictionary[CamRelayConstructingCaptureOutputKey] boolValue];
}

static NSString *CamRelayRuntimeArchitecture(void) {
#if defined(__x86_64__)
    return @"x86_64";
#elif defined(__arm64__)
    return @"arm64";
#else
    return @"unknown";
#endif
}

static id CamRelayBeginCaptureOutputConstruction(void) {
    NSMutableDictionary *threadDictionary = NSThread.currentThread.threadDictionary;
    id previous = threadDictionary[CamRelayConstructingCaptureOutputKey];
    threadDictionary[CamRelayConstructingCaptureOutputKey] = @YES;
    return previous;
}

static void CamRelayEndCaptureOutputConstruction(id previous) {
    NSMutableDictionary *threadDictionary = NSThread.currentThread.threadDictionary;
    if (previous != nil) {
        threadDictionary[CamRelayConstructingCaptureOutputKey] = previous;
    } else {
        [threadDictionary removeObjectForKey:CamRelayConstructingCaptureOutputKey];
    }
}

static NSInteger CamRelayEnvironmentInteger(const char *name, NSInteger fallback, NSInteger maximum) {
    const char *value = getenv(name);
    if (value == NULL) {
        return fallback;
    }
    long parsed = strtol(value, NULL, 10);
    if (parsed <= 0 || parsed > maximum) {
        return fallback;
    }
    return (NSInteger)parsed;
}

static int CamRelayConnectToFrameServer(void) {
    NSInteger port = CamRelayEnvironmentInteger("CAMRELAY_PORT", 0, UINT16_MAX);
    if (port == 0) {
        return -1;
    }

    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor < 0) {
        return -1;
    }
    int noSigPipe = 1;
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)port);
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    if (connect(descriptor, (const struct sockaddr *)&address, sizeof(address)) != 0) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

static BOOL CamRelaySendClientRole(int descriptor, uint8_t role) {
    return send(descriptor, &role, sizeof(role), 0) == sizeof(role);
}

static BOOL CamRelayIsActive(void) {
    return atomic_load_explicit(&CamRelayRuntimeActive, memory_order_acquire);
}

static BOOL CamRelayStartControlConnection(void) {
    int descriptor = CamRelayConnectToFrameServer();
    if (descriptor < 0 || !CamRelaySendClientRole(descriptor, CamRelayControlClientRole)) {
        if (descriptor >= 0) {
            close(descriptor);
        }
        return NO;
    }

    struct timeval timeout = {.tv_sec = 2, .tv_usec = 0};
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    uint8_t response = 0;
    if (recv(descriptor, &response, sizeof(response), 0) != sizeof(response) ||
        response != CamRelayControlClientRole) {
        close(descriptor);
        return NO;
    }

    timeout = (struct timeval){0};
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    atomic_store_explicit(&CamRelayRuntimeActive, true, memory_order_release);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        uint8_t byte = 0;
        while (recv(descriptor, &byte, sizeof(byte), 0) > 0) {}
        atomic_store_explicit(&CamRelayRuntimeActive, false, memory_order_release);
        close(descriptor);
        NSLog(@"[CamRelayRuntime] Simulator relay stopped");
    });
    return YES;
}

static size_t CamRelayFixtureWidth(void) {
    return (size_t)CamRelayEnvironmentInteger("CAMRELAY_WIDTH", 1280, 4096);
}

static size_t CamRelayFixtureHeight(void) {
    return (size_t)CamRelayEnvironmentInteger("CAMRELAY_HEIGHT", 720, 4096);
}

static int32_t CamRelayFixtureFramesPerSecond(void) {
    return (int32_t)CamRelayEnvironmentInteger("CAMRELAY_FPS", 30, 120);
}

static CIContext *CamRelayImageContext(void) {
    static CIContext *context;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    });
    return context;
}

static NSValue *CamRelayValueWithPoint(CGPoint point) {
    return [NSValue value:&point withObjCType:@encode(CGPoint)];
}

static CGPoint CamRelayPointFromValue(NSValue *value, CGPoint fallback) {
    if (value == nil || strcmp(value.objCType, @encode(CGPoint)) != 0) {
        return fallback;
    }
    CGPoint point;
    [value getValue:&point size:sizeof(point)];
    return point;
}

static CMVideoFormatDescriptionRef CamRelayFixtureFormatDescription(void) {
    static CMVideoFormatDescriptionRef formatDescription;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CMVideoFormatDescriptionCreate(
            kCFAllocatorDefault,
            kCVPixelFormatType_32BGRA,
            (int32_t)CamRelayFixtureWidth(),
            (int32_t)CamRelayFixtureHeight(),
            NULL,
            &formatDescription
        );
    });
    return formatDescription;
}

@interface CamRelaySyntheticFrameRateRange : AVFrameRateRange
@end

@implementation CamRelaySyntheticFrameRateRange
- (Float64)minFrameRate { return CamRelayFixtureFramesPerSecond(); }
- (Float64)maxFrameRate { return CamRelayFixtureFramesPerSecond(); }
- (CMTime)minFrameDuration { return CMTimeMake(1, CamRelayFixtureFramesPerSecond()); }
- (CMTime)maxFrameDuration { return CMTimeMake(1, CamRelayFixtureFramesPerSecond()); }
@end

static AVFrameRateRange *CamRelayFrameRateRange(void) {
    static AVFrameRateRange *range;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        range = class_createInstance(CamRelaySyntheticFrameRateRange.class, 0);
    });
    return range;
}

@interface CamRelaySyntheticDeviceFormat : AVCaptureDeviceFormat
@end

@implementation CamRelaySyntheticDeviceFormat
- (AVMediaType)mediaType { return AVMediaTypeVideo; }
- (CMFormatDescriptionRef)formatDescription { return CamRelayFixtureFormatDescription(); }
- (NSArray<AVFrameRateRange *> *)videoSupportedFrameRateRanges { return @[CamRelayFrameRateRange()]; }
- (float)videoFieldOfView { return 60.0f; }
- (BOOL)isVideoBinned { return NO; }
- (BOOL)isVideoStabilizationModeSupported:(AVCaptureVideoStabilizationMode)mode {
    return mode == AVCaptureVideoStabilizationModeOff || mode == AVCaptureVideoStabilizationModeAuto;
}
- (BOOL)isVideoStabilizationSupported { return YES; }
- (CGFloat)videoMaxZoomFactor { return 8.0; }
- (CGFloat)videoZoomFactorUpscaleThreshold { return 1.0; }
- (AVZoomRange *)systemRecommendedVideoZoomRange { return nil; }
- (CMTime)minExposureDuration { return CMTimeMake(1, 1000); }
- (CMTime)maxExposureDuration { return CMTimeMake(1, 3); }
- (AVExposureBiasRange *)systemRecommendedExposureBiasRange { return nil; }
- (float)minISO { return 25.0f; }
- (float)maxISO { return 1600.0f; }
- (BOOL)isGlobalToneMappingSupported { return NO; }
- (BOOL)isVideoHDRSupported { return NO; }
- (BOOL)isHighPhotoQualitySupported { return YES; }
- (BOOL)isHighestPhotoQualitySupported { return YES; }
- (BOOL)supportsHighResolutionStillImageOutput { return YES; }
- (BOOL)supportsQuadraHighResolutionStillImageOutput { return NO; }
- (BOOL)isZeroShutterLagSupported { return NO; }
- (BOOL)isUltraHighResolutionZeroShutterLagSupported { return NO; }
- (BOOL)isFastCapturePrioritizationSupported { return NO; }
- (BOOL)isDeferredPhotoProcessingSupported { return NO; }
- (CMVideoDimensions)highResolutionStillImageDimensions {
    return (CMVideoDimensions){(int32_t)CamRelayFixtureWidth(), (int32_t)CamRelayFixtureHeight()};
}
- (CMVideoDimensions)defaultPhotoDimensionsWithHighResolutionCaptureEnabled:(BOOL)enabled {
    return (CMVideoDimensions){(int32_t)CamRelayFixtureWidth(), (int32_t)CamRelayFixtureHeight()};
}
- (NSArray<NSValue *> *)supportedMaxPhotoDimensions {
    CMVideoDimensions dimensions = {(int32_t)CamRelayFixtureWidth(), (int32_t)CamRelayFixtureHeight()};
    return @[[NSValue valueWithCMVideoDimensions:dimensions]];
}
- (NSArray<NSValue *> *)supportedMaxPhotoDimensionsPrivate {
    return self.supportedMaxPhotoDimensions;
}
- (NSArray<NSValue *> *)_supportedMaxPhotoDimensionsPrivateDimensionsEnabled:(BOOL)enabled {
    return self.supportedMaxPhotoDimensions;
}
- (BOOL)validateMaxPhotoDimensions:(CMVideoDimensions)dimensions
    privateDimensionsEnabled:(BOOL)enabled {
    return dimensions.width == (int32_t)CamRelayFixtureWidth() &&
        dimensions.height == (int32_t)CamRelayFixtureHeight();
}
- (BOOL)maxPhotoDimensionsAreUltraHighResolution:(CMVideoDimensions)dimensions
    privateDimensionsEnabled:(BOOL)enabled {
    return NO;
}
- (AVCaptureAutoFocusSystem)autoFocusSystem { return AVCaptureAutoFocusSystemContrastDetection; }
- (NSArray<NSNumber *> *)supportedColorSpaces { return @[@(AVCaptureColorSpace_sRGB)]; }
- (CGFloat)videoMinZoomFactorForDepthDataDelivery { return 1.0; }
- (CGFloat)videoMaxZoomFactorForDepthDataDelivery { return 1.0; }
- (NSArray<NSNumber *> *)supportedVideoZoomFactorsForDepthDataDelivery { return @[]; }
- (NSArray<AVZoomRange *> *)supportedVideoZoomRangesForDepthDataDelivery { return @[]; }
- (BOOL)zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported { return NO; }
- (NSArray<AVCaptureDeviceFormat *> *)supportedDepthDataFormats { return @[]; }
- (NSArray<Class> *)unsupportedCaptureOutputClasses { return @[AVCaptureDepthDataOutput.class]; }
- (NSArray<NSNumber *> *)secondaryNativeResolutionZoomFactors { return @[]; }
- (BOOL)isAutoVideoFrameRateSupported { return NO; }
- (BOOL)isPortraitEffectsMatteStillImageDeliverySupported { return NO; }
- (BOOL)isMultiCamSupported { return NO; }
- (BOOL)isSpatialVideoCaptureSupported { return NO; }
- (float)geometricDistortionCorrectedVideoFieldOfView { return self.videoFieldOfView; }
- (BOOL)isCenterStageSupported { return NO; }
- (CGFloat)videoMinZoomFactorForCenterStage { return 1.0; }
- (CGFloat)videoMaxZoomFactorForCenterStage { return self.videoMaxZoomFactor; }
- (AVFrameRateRange *)videoFrameRateRangeForCenterStage { return nil; }
- (BOOL)isPortraitEffectSupported { return NO; }
- (AVFrameRateRange *)videoFrameRateRangeForPortraitEffect { return nil; }
- (BOOL)isStudioLightSupported { return NO; }
- (AVFrameRateRange *)videoFrameRateRangeForStudioLight { return nil; }
- (BOOL)reactionEffectsSupported { return NO; }
- (AVFrameRateRange *)videoFrameRateRangeForReactionEffectsInProgress { return nil; }
- (BOOL)isBackgroundReplacementSupported { return NO; }
- (AVFrameRateRange *)videoFrameRateRangeForBackgroundReplacement { return nil; }
- (NSString *)description {
    return [NSString stringWithFormat:@"<CamRelay format %zux%zu @ %d fps>",
        CamRelayFixtureWidth(), CamRelayFixtureHeight(), CamRelayFixtureFramesPerSecond()];
}
@end

static AVCaptureDeviceFormat *CamRelayDeviceFormat(void) {
    static AVCaptureDeviceFormat *format;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        format = class_createInstance(CamRelaySyntheticDeviceFormat.class, 0);
    });
    return format;
}

@interface CamRelaySyntheticDevice : AVCaptureDevice
@end

@implementation CamRelaySyntheticDevice

- (AVCaptureDevicePosition)position {
    return (AVCaptureDevicePosition)[objc_getAssociatedObject(self, CamRelayDevicePositionKey) integerValue];
}
- (NSString *)uniqueID {
    return self.position == AVCaptureDevicePositionFront
        ? @"org.camrelay.synthetic.front"
        : @"org.camrelay.synthetic.back";
}
- (NSString *)modelID { return @"CamRelaySyntheticCamera"; }
- (NSString *)localizedName {
    return self.position == AVCaptureDevicePositionFront ? @"CamRelay Front Camera" : @"CamRelay Back Camera";
}
- (NSString *)manufacturer { return @"CamRelay"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isConnected { return YES; }
- (BOOL)isSuspended { return NO; }
- (BOOL)isInUseByAnotherApplication { return NO; }
- (BOOL)hasMediaType:(AVMediaType)mediaType { return [mediaType isEqualToString:AVMediaTypeVideo]; }
- (BOOL)supportsAVCaptureSessionPreset:(AVCaptureSessionPreset)preset { return YES; }
- (NSArray<AVCaptureDeviceFormat *> *)formats { return @[CamRelayDeviceFormat()]; }
- (AVCaptureDeviceFormat *)activeFormat {
    return objc_getAssociatedObject(self, CamRelayDeviceActiveFormatKey) ?: CamRelayDeviceFormat();
}
- (void)setActiveFormat:(AVCaptureDeviceFormat *)format {
    if ([format isKindOfClass:CamRelaySyntheticDeviceFormat.class]) {
        objc_setAssociatedObject(self, CamRelayDeviceActiveFormatKey, format, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
- (BOOL)lockForConfiguration:(NSError **)outError {
    if (outError != NULL) {
        *outError = nil;
    }
    return YES;
}
- (void)unlockForConfiguration {}

- (CMTime)activeVideoMinFrameDuration {
    NSValue *value = objc_getAssociatedObject(self, CamRelayDeviceMinFrameDurationKey);
    return value != nil ? value.CMTimeValue : CMTimeMake(1, CamRelayFixtureFramesPerSecond());
}
- (void)setActiveVideoMinFrameDuration:(CMTime)duration {
    objc_setAssociatedObject(
        self,
        CamRelayDeviceMinFrameDurationKey,
        [NSValue valueWithCMTime:duration],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}
- (CMTime)activeVideoMaxFrameDuration {
    NSValue *value = objc_getAssociatedObject(self, CamRelayDeviceMaxFrameDurationKey);
    return value != nil ? value.CMTimeValue : CMTimeMake(1, CamRelayFixtureFramesPerSecond());
}
- (void)setActiveVideoMaxFrameDuration:(CMTime)duration {
    objc_setAssociatedObject(
        self,
        CamRelayDeviceMaxFrameDurationKey,
        [NSValue valueWithCMTime:duration],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

- (BOOL)isFocusModeSupported:(AVCaptureFocusMode)mode { return YES; }
- (AVCaptureFocusMode)focusMode {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayDeviceFocusModeKey);
    return value != nil ? value.integerValue : AVCaptureFocusModeContinuousAutoFocus;
}
- (void)setFocusMode:(AVCaptureFocusMode)mode {
    objc_setAssociatedObject(self, CamRelayDeviceFocusModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isFocusPointOfInterestSupported { return YES; }
- (CGPoint)focusPointOfInterest {
    NSValue *value = objc_getAssociatedObject(self, CamRelayDeviceFocusPointKey);
    return CamRelayPointFromValue(value, CGPointMake(0.5, 0.5));
}
- (void)setFocusPointOfInterest:(CGPoint)point {
    objc_setAssociatedObject(
        self,
        CamRelayDeviceFocusPointKey,
        CamRelayValueWithPoint(point),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}
- (BOOL)isAdjustingFocus { return NO; }
- (float)lensPosition { return 1.0f; }
- (BOOL)isSmoothAutoFocusSupported { return YES; }
- (BOOL)isSmoothAutoFocusEnabled { return YES; }
- (void)setSmoothAutoFocusEnabled:(BOOL)enabled {}

- (BOOL)isExposureModeSupported:(AVCaptureExposureMode)mode { return YES; }
- (AVCaptureExposureMode)exposureMode {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayDeviceExposureModeKey);
    return value != nil ? value.integerValue : AVCaptureExposureModeContinuousAutoExposure;
}
- (void)setExposureMode:(AVCaptureExposureMode)mode {
    objc_setAssociatedObject(self, CamRelayDeviceExposureModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isExposurePointOfInterestSupported { return YES; }
- (CGPoint)exposurePointOfInterest {
    NSValue *value = objc_getAssociatedObject(self, CamRelayDeviceExposurePointKey);
    return CamRelayPointFromValue(value, CGPointMake(0.5, 0.5));
}
- (void)setExposurePointOfInterest:(CGPoint)point {
    objc_setAssociatedObject(
        self,
        CamRelayDeviceExposurePointKey,
        CamRelayValueWithPoint(point),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}
- (BOOL)isAdjustingExposure { return NO; }
- (CMTime)exposureDuration { return CMTimeMake(1, CamRelayFixtureFramesPerSecond()); }
- (float)ISO { return 100.0f; }
- (float)exposureTargetOffset { return 0.0f; }
- (float)exposureTargetBias { return 0.0f; }
- (float)minExposureTargetBias { return -8.0f; }
- (float)maxExposureTargetBias { return 8.0f; }
- (void)setExposureModeCustomWithDuration:(CMTime)duration
    ISO:(float)ISO
    completionHandler:(void (^)(CMTime syncTime))handler {
    if (handler != nil) {
        handler(CMClockGetTime(CMClockGetHostTimeClock()));
    }
}
- (void)setExposureTargetBias:(float)bias completionHandler:(void (^)(CMTime syncTime))handler {
    if (handler != nil) {
        handler(CMClockGetTime(CMClockGetHostTimeClock()));
    }
}

- (BOOL)isWhiteBalanceModeSupported:(AVCaptureWhiteBalanceMode)mode { return YES; }
- (AVCaptureWhiteBalanceMode)whiteBalanceMode {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayDeviceWhiteBalanceModeKey);
    return value != nil ? value.integerValue : AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
}
- (void)setWhiteBalanceMode:(AVCaptureWhiteBalanceMode)mode {
    objc_setAssociatedObject(self, CamRelayDeviceWhiteBalanceModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isAdjustingWhiteBalance { return NO; }
- (AVCaptureWhiteBalanceGains)deviceWhiteBalanceGains {
    return (AVCaptureWhiteBalanceGains){1.0f, 1.0f, 1.0f};
}
- (float)maxWhiteBalanceGain { return 4.0f; }
- (void)setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains
    completionHandler:(void (^)(CMTime syncTime))handler {
    if (handler != nil) {
        handler(CMClockGetTime(CMClockGetHostTimeClock()));
    }
}

- (BOOL)hasFlash { return NO; }
- (BOOL)isFlashAvailable { return NO; }
- (BOOL)isFlashActive { return NO; }
- (BOOL)isFlashModeSupported:(AVCaptureFlashMode)mode { return mode == AVCaptureFlashModeOff; }
- (AVCaptureFlashMode)flashMode { return AVCaptureFlashModeOff; }
- (void)setFlashMode:(AVCaptureFlashMode)mode {}
- (BOOL)hasTorch { return NO; }
- (BOOL)isTorchAvailable { return NO; }
- (BOOL)isTorchActive { return NO; }
- (BOOL)isTorchModeSupported:(AVCaptureTorchMode)mode { return mode == AVCaptureTorchModeOff; }
- (AVCaptureTorchMode)torchMode { return AVCaptureTorchModeOff; }
- (void)setTorchMode:(AVCaptureTorchMode)mode {}
- (BOOL)setTorchModeOnWithLevel:(float)torchLevel error:(NSError **)outError {
    if (outError != NULL) {
        *outError = [NSError errorWithDomain:@"CamRelayRuntime" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"The synthetic camera does not provide a torch."
        }];
    }
    return NO;
}

- (CGFloat)videoZoomFactor {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayDeviceZoomKey);
    return value != nil ? value.doubleValue : 1.0;
}
- (void)setVideoZoomFactor:(CGFloat)factor {
    CGFloat clamped = MAX(1.0, MIN(8.0, factor));
    objc_setAssociatedObject(self, CamRelayDeviceZoomKey, @(clamped), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (CGFloat)minAvailableVideoZoomFactor { return 1.0; }
- (CGFloat)maxAvailableVideoZoomFactor { return 8.0; }
- (void)rampToVideoZoomFactor:(CGFloat)factor withRate:(float)rate { self.videoZoomFactor = factor; }
- (BOOL)isRampingVideoZoom { return NO; }
- (void)cancelVideoZoomRamp {}
- (BOOL)isSubjectAreaChangeMonitoringEnabled { return NO; }
- (void)setSubjectAreaChangeMonitoringEnabled:(BOOL)enabled {}
- (BOOL)isLowLightBoostSupported { return NO; }
- (BOOL)isLowLightBoostEnabled { return NO; }
- (BOOL)isVirtualDevice { return NO; }
- (NSArray<AVCaptureDevice *> *)constituentDevices { return @[]; }

@end

static AVCaptureDevice *CamRelayDevice(AVCaptureDevicePosition position) {
    static AVCaptureDevice *frontDevice;
    static AVCaptureDevice *backDevice;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        frontDevice = class_createInstance(CamRelaySyntheticDevice.class, 0);
        objc_setAssociatedObject(
            frontDevice,
            CamRelayDevicePositionKey,
            @(AVCaptureDevicePositionFront),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        backDevice = class_createInstance(CamRelaySyntheticDevice.class, 0);
        objc_setAssociatedObject(
            backDevice,
            CamRelayDevicePositionKey,
            @(AVCaptureDevicePositionBack),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    });
    return position == AVCaptureDevicePositionFront ? frontDevice : backDevice;
}

static NSArray<AVCaptureDevice *> *CamRelayVideoDevicesForPosition(AVCaptureDevicePosition position) {
    switch (position) {
    case AVCaptureDevicePositionFront:
        return @[CamRelayDevice(AVCaptureDevicePositionFront)];
    case AVCaptureDevicePositionBack:
        return @[CamRelayDevice(AVCaptureDevicePositionBack)];
    default:
        return @[
            CamRelayDevice(AVCaptureDevicePositionBack),
            CamRelayDevice(AVCaptureDevicePositionFront),
        ];
    }
}

@interface CamRelaySyntheticInputPort : AVCaptureInputPort
@end

@implementation CamRelaySyntheticInputPort
- (AVCaptureInput *)input { return objc_getAssociatedObject(self, CamRelayPortInputKey); }
- (AVMediaType)mediaType { return AVMediaTypeVideo; }
- (CMFormatDescriptionRef)formatDescription {
    AVCaptureDeviceInput *input = (AVCaptureDeviceInput *)self.input;
    return input.device.activeFormat.formatDescription;
}
- (BOOL)isEnabled {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayPortEnabledKey);
    return value == nil || value.boolValue;
}
- (void)setEnabled:(BOOL)enabled {
    objc_setAssociatedObject(self, CamRelayPortEnabledKey, @(enabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (CMClockRef)clock { return CMClockGetHostTimeClock(); }
- (AVCaptureDeviceType)sourceDeviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (AVCaptureDevicePosition)sourceDevicePosition {
    return ((AVCaptureDeviceInput *)self.input).device.position;
}
@end

@interface CamRelaySyntheticDeviceInput : AVCaptureDeviceInput
@end

@implementation CamRelaySyntheticDeviceInput
- (AVCaptureDevice *)device { return objc_getAssociatedObject(self, CamRelayInputDeviceKey); }
- (NSArray<AVCaptureInputPort *> *)ports {
    AVCaptureInputPort *port = objc_getAssociatedObject(self, CamRelayInputPortKey);
    if (port == nil) {
        port = class_createInstance(CamRelaySyntheticInputPort.class, 0);
        objc_setAssociatedObject(port, CamRelayPortInputKey, self, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(self, CamRelayInputPortKey, port, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return @[port];
}
- (NSArray<AVCaptureInputPort *> *)portsWithMediaType:(AVMediaType)mediaType
    sourceDeviceType:(AVCaptureDeviceType)sourceDeviceType
    sourceDevicePosition:(AVCaptureDevicePosition)sourceDevicePosition {
    if (![mediaType isEqualToString:AVMediaTypeVideo]) {
        return @[];
    }
    if (sourceDeviceType != nil && ![sourceDeviceType isEqualToString:self.device.deviceType]) {
        return @[];
    }
    if (sourceDevicePosition != AVCaptureDevicePositionUnspecified &&
        sourceDevicePosition != self.device.position) {
        return @[];
    }
    return self.ports;
}
@end

@interface CamRelaySyntheticConnection : AVCaptureConnection
@end

@implementation CamRelaySyntheticConnection
- (AVMediaType)mediaType { return self.inputPorts.firstObject.mediaType ?: AVMediaTypeVideo; }
- (NSArray<AVCaptureInputPort *> *)inputPorts {
    return objc_getAssociatedObject(self, CamRelayConnectionInputPortsKey) ?: @[];
}
- (AVCaptureDeviceInput *)sourceDeviceInput {
    AVCaptureInput *input = self.inputPorts.firstObject.input;
    return [input isKindOfClass:CamRelaySyntheticDeviceInput.class]
        ? (AVCaptureDeviceInput *)input
        : nil;
}
- (AVCaptureDevice *)sourceDevice {
    return self.sourceDeviceInput.device;
}
- (BOOL)sourcesFromFrontFacingCamera {
    return self.sourceDevice.position == AVCaptureDevicePositionFront;
}
- (BOOL)sourcesFromExternalCamera { return NO; }
- (AVCaptureOutput *)output { return objc_getAssociatedObject(self, CamRelayConnectionOutputKey); }
- (AVCaptureVideoPreviewLayer *)videoPreviewLayer {
    return objc_getAssociatedObject(self, CamRelayConnectionPreviewLayerKey);
}
- (BOOL)isEnabled {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayConnectionEnabledKey);
    return value == nil || value.boolValue;
}
- (void)setEnabled:(BOOL)enabled {
    objc_setAssociatedObject(self, CamRelayConnectionEnabledKey, @(enabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isActive { return self.isEnabled; }
- (NSArray<AVCaptureAudioChannel *> *)audioChannels { return @[]; }
- (BOOL)isVideoMirroringSupported { return YES; }
- (BOOL)automaticallyAdjustsVideoMirroring {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayConnectionAutoMirrorKey);
    return value == nil || value.boolValue;
}
- (void)setAutomaticallyAdjustsVideoMirroring:(BOOL)value {
    objc_setAssociatedObject(self, CamRelayConnectionAutoMirrorKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isVideoMirrored {
    return [objc_getAssociatedObject(self, CamRelayConnectionMirroredKey) boolValue];
}
- (void)setVideoMirrored:(BOOL)value {
    objc_setAssociatedObject(self, CamRelayConnectionMirroredKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isVideoOrientationSupported { return YES; }
- (AVCaptureVideoOrientation)videoOrientation {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayConnectionOrientationKey);
    return value != nil ? value.integerValue : AVCaptureVideoOrientationLandscapeLeft;
}
- (void)setVideoOrientation:(AVCaptureVideoOrientation)value {
    objc_setAssociatedObject(self, CamRelayConnectionOrientationKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isVideoRotationAngleSupported:(CGFloat)angle {
    if (!isfinite(angle)) {
        return NO;
    }
    CGFloat normalized = fmod(fmod(angle, 360.0) + 360.0, 360.0);
    return fabs(normalized - 0.0) < 0.01 ||
        fabs(normalized - 90.0) < 0.01 ||
        fabs(normalized - 180.0) < 0.01 ||
        fabs(normalized - 270.0) < 0.01;
}
- (CGFloat)videoRotationAngle {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayConnectionRotationKey);
    return value != nil ? value.doubleValue : 0.0;
}
- (void)setVideoRotationAngle:(CGFloat)value {
    if ([self isVideoRotationAngleSupported:value]) {
        CGFloat normalized = fmod(fmod(value, 360.0) + 360.0, 360.0);
        objc_setAssociatedObject(
            self,
            CamRelayConnectionRotationKey,
            @(normalized),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}
- (BOOL)isVideoStabilizationSupported { return YES; }
- (AVCaptureVideoStabilizationMode)preferredVideoStabilizationMode {
    NSNumber *value = objc_getAssociatedObject(self, CamRelayConnectionStabilizationKey);
    return value != nil ? value.integerValue : AVCaptureVideoStabilizationModeOff;
}
- (void)setPreferredVideoStabilizationMode:(AVCaptureVideoStabilizationMode)value {
    objc_setAssociatedObject(self, CamRelayConnectionStabilizationKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (AVCaptureVideoStabilizationMode)activeVideoStabilizationMode {
    return self.preferredVideoStabilizationMode;
}
- (BOOL)isCameraIntrinsicMatrixDeliverySupported { return NO; }
- (BOOL)isCameraIntrinsicMatrixDeliveryEnabled { return NO; }
- (void)setCameraIntrinsicMatrixDeliveryEnabled:(BOOL)value {}
@end

static AVCaptureConnection *CamRelayConnection(
    NSArray<AVCaptureInputPort *> *ports,
    AVCaptureOutput *output,
    AVCaptureVideoPreviewLayer *previewLayer
) {
    AVCaptureConnection *connection = class_createInstance(CamRelaySyntheticConnection.class, 0);
    objc_setAssociatedObject(
        connection,
        CamRelayConnectionInputPortsKey,
        ports ?: @[],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    if (output != nil) {
        objc_setAssociatedObject(
            connection,
            CamRelayConnectionOutputKey,
            output,
            OBJC_ASSOCIATION_ASSIGN
        );
    }
    if (previewLayer != nil) {
        objc_setAssociatedObject(
            connection,
            CamRelayConnectionPreviewLayerKey,
            previewLayer,
            OBJC_ASSOCIATION_ASSIGN
        );
    }
    return connection;
}

static NSMutableArray *CamRelayMutableArray(id object, const void *key) {
    NSMutableArray *array = objc_getAssociatedObject(object, key);
    if (array == nil) {
        array = [NSMutableArray array];
        objc_setAssociatedObject(object, key, array, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return array;
}

static BOOL CamRelaySessionUsesSyntheticCamera(AVCaptureSession *session) {
    return [objc_getAssociatedObject(session, CamRelaySyntheticInputsKey) count] > 0;
}

static BOOL CamRelaySupportsOutput(AVCaptureOutput *output) {
    return [output isKindOfClass:AVCaptureVideoDataOutput.class] ||
        [output isKindOfClass:AVCapturePhotoOutput.class] ||
        [output isKindOfClass:AVCaptureMovieFileOutput.class] ||
        [output isKindOfClass:AVCaptureMetadataOutput.class];
}

static AVCaptureInputPort *CamRelayFirstVideoPort(AVCaptureSession *session) {
    for (AVCaptureDeviceInput *input in CamRelayMutableArray(session, CamRelaySyntheticInputsKey)) {
        AVCaptureInputPort *port = input.ports.firstObject;
        if ([port.mediaType isEqualToString:AVMediaTypeVideo]) {
            return port;
        }
    }
    return nil;
}

static void CamRelayAddConnectionToSession(AVCaptureSession *session, AVCaptureConnection *connection) {
    NSMutableArray *connections = CamRelayMutableArray(session, CamRelaySyntheticConnectionsKey);
    if (![connections containsObject:connection]) {
        [connections addObject:connection];
    }
    AVCaptureOutput *output = connection.output;
    if (output != nil) {
        objc_setAssociatedObject(output, CamRelayOutputConnectionKey, connection, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(output, CamRelayOutputSessionKey, session, OBJC_ASSOCIATION_ASSIGN);
    }
    AVCaptureVideoPreviewLayer *layer = connection.videoPreviewLayer;
    if (layer != nil) {
        objc_setAssociatedObject(layer, CamRelayPreviewConnectionKey, connection, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void CamRelayEnsureOutputConnection(AVCaptureSession *session, AVCaptureOutput *output) {
    if (objc_getAssociatedObject(output, CamRelayOutputConnectionKey) != nil) {
        return;
    }
    AVCaptureInputPort *port = CamRelayFirstVideoPort(session);
    if (port == nil) {
        return;
    }
    CamRelayAddConnectionToSession(session, CamRelayConnection(@[port], output, nil));
}

static void CamRelayRegisterPreviewLayer(
    AVCaptureVideoPreviewLayer *layer,
    AVCaptureSession *session,
    BOOL createConnection
) {
    if (layer == nil || session == nil) {
        return;
    }
    NSHashTable *layers = objc_getAssociatedObject(session, CamRelayPreviewLayersKey);
    if (layers == nil) {
        layers = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(session, CamRelayPreviewLayersKey, layers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [layers addObject:layer];
    if (!CamRelaySessionUsesSyntheticCamera(session)) {
        return;
    }
    AVSampleBufferDisplayLayer *displayLayer = objc_getAssociatedObject(
        layer,
        CamRelayPreviewDisplayLayerKey
    );
    if (displayLayer == nil) {
        @synchronized(layer) {
            displayLayer = objc_getAssociatedObject(layer, CamRelayPreviewDisplayLayerKey);
            if (displayLayer == nil) {
                displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
                displayLayer.videoGravity = layer.videoGravity;
                displayLayer.opaque = YES;
                objc_setAssociatedObject(
                    layer,
                    CamRelayPreviewDisplayLayerKey,
                    displayLayer,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC
                );
            }
        }
    }
    void (^installDisplayLayer)(void) = ^{
        displayLayer.frame = layer.bounds;
        displayLayer.videoGravity = layer.videoGravity;
        if (displayLayer.superlayer != layer) {
            [layer addSublayer:displayLayer];
        }
    };
    if (NSThread.isMainThread) {
        installDisplayLayer();
    } else {
        dispatch_async(dispatch_get_main_queue(), installDisplayLayer);
    }
    if (createConnection && objc_getAssociatedObject(layer, CamRelayPreviewConnectionKey) == nil) {
        AVCaptureInputPort *port = CamRelayFirstVideoPort(session);
        if (port != nil) {
            CamRelayAddConnectionToSession(session, CamRelayConnection(@[port], nil, layer));
        }
    }
}

static CMSampleBufferRef CamRelayCreateFrame(
    const uint8_t *bytes,
    size_t width,
    size_t height,
    size_t sourceBytesPerRow,
    uint64_t presentationTimeNanoseconds,
    uint64_t durationNanoseconds
) {
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
    };

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn pixelResult = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attributes,
        &pixelBuffer
    );
    if (pixelResult != kCVReturnSuccess || pixelBuffer == NULL) {
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    uint8_t *destination = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t destinationBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    for (size_t row = 0; row < height; row += 1) {
        memcpy(
            destination + row * destinationBytesPerRow,
            bytes + row * sourceBytesPerRow,
            width * 4
        );
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    CMVideoFormatDescriptionRef format = NULL;
    OSStatus formatResult = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        &format
    );
    if (formatResult != noErr || format == NULL) {
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }

    CMSampleTimingInfo timing = {
        .duration = CMTimeMake((int64_t)durationNanoseconds, 1000000000),
        .presentationTimeStamp = CMTimeMake(
            (int64_t)presentationTimeNanoseconds,
            1000000000
        ),
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus sampleResult = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        format,
        &timing,
        &sampleBuffer
    );

    CFRelease(format);
    CVPixelBufferRelease(pixelBuffer);
    return sampleResult == noErr ? sampleBuffer : NULL;
}

static CGImagePropertyOrientation CamRelayOrientationForRotation(
    CGFloat rotation,
    BOOL mirrored
) {
    if (fabs(rotation - 90.0) < 0.01) {
        return mirrored ? kCGImagePropertyOrientationRightMirrored : kCGImagePropertyOrientationRight;
    }
    if (fabs(rotation - 180.0) < 0.01) {
        return mirrored ? kCGImagePropertyOrientationDownMirrored : kCGImagePropertyOrientationDown;
    }
    if (fabs(rotation - 270.0) < 0.01) {
        return mirrored ? kCGImagePropertyOrientationLeftMirrored : kCGImagePropertyOrientationLeft;
    }
    return mirrored ? kCGImagePropertyOrientationUpMirrored : kCGImagePropertyOrientationUp;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static CGImagePropertyOrientation CamRelayImageOrientation(AVCaptureConnection *connection) {
    BOOL mirrored = connection.isVideoMirrored;
    NSNumber *rotation = objc_getAssociatedObject(connection, CamRelayConnectionRotationKey);
    if (rotation != nil) {
        return CamRelayOrientationForRotation(rotation.doubleValue, mirrored);
    }
    switch (connection.videoOrientation) {
    case AVCaptureVideoOrientationPortrait:
        return mirrored ? kCGImagePropertyOrientationRightMirrored : kCGImagePropertyOrientationRight;
    case AVCaptureVideoOrientationPortraitUpsideDown:
        return mirrored ? kCGImagePropertyOrientationLeftMirrored : kCGImagePropertyOrientationLeft;
    case AVCaptureVideoOrientationLandscapeLeft:
        return mirrored ? kCGImagePropertyOrientationUpMirrored : kCGImagePropertyOrientationUp;
    case AVCaptureVideoOrientationLandscapeRight:
        return mirrored ? kCGImagePropertyOrientationDownMirrored : kCGImagePropertyOrientationDown;
    }
}
#pragma clang diagnostic pop

static CMSampleBufferRef CamRelayCopySampleForVideoOutput(
    CMSampleBufferRef source,
    AVCaptureVideoDataOutput *output,
    AVCaptureConnection *connection
) {
    CVPixelBufferRef sourceBuffer = CMSampleBufferGetImageBuffer(source);
    if (sourceBuffer == NULL) {
        return NULL;
    }

    NSNumber *requestedType = output.videoSettings[(NSString *)kCVPixelBufferPixelFormatTypeKey];
    OSType pixelFormat = requestedType != nil ? requestedType.unsignedIntValue : kCVPixelFormatType_32BGRA;
    CGImagePropertyOrientation orientation = CamRelayImageOrientation(connection);
    BOOL transformImage = orientation != kCGImagePropertyOrientationUp;
    if (pixelFormat == kCVPixelFormatType_32BGRA && !transformImage) {
        CFRetain(source);
        return source;
    }

    CIImage *image = [CIImage imageWithCVPixelBuffer:sourceBuffer];
    if (transformImage) {
        image = [image imageByApplyingCGOrientation:orientation];
    }
    CGRect extent = CGRectIntegral(image.extent);
    size_t width = (size_t)CGRectGetWidth(extent);
    size_t height = (size_t)CGRectGetHeight(extent);
    NSDictionary *attributes = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVPixelBufferRef destination = NULL;
    CVReturn createResult = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        pixelFormat,
        (__bridge CFDictionaryRef)attributes,
        &destination
    );
    if (createResult != kCVReturnSuccess || destination == NULL) {
        return NULL;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    [CamRelayImageContext() render:image
                   toCVPixelBuffer:destination
                            bounds:extent
                        colorSpace:colorSpace];
    CGColorSpaceRelease(colorSpace);

    CMVideoFormatDescriptionRef format = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(
            kCFAllocatorDefault,
            destination,
            &format
        ) != noErr || format == NULL) {
        CVPixelBufferRelease(destination);
        return NULL;
    }
    CMSampleTimingInfo timing;
    CMSampleBufferGetSampleTimingInfo(source, 0, &timing);
    CMSampleBufferRef transformed = NULL;
    OSStatus result = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        destination,
        format,
        &timing,
        &transformed
    );
    CFRelease(format);
    CVPixelBufferRelease(destination);
    return result == noErr ? transformed : NULL;
}

@interface CamRelaySyntheticResolvedPhotoSettings : AVCaptureResolvedPhotoSettings
@end

@implementation CamRelaySyntheticResolvedPhotoSettings
- (int64_t)uniqueID { return [objc_getAssociatedObject(self, CamRelayResolvedUniqueIDKey) longLongValue]; }
- (CMVideoDimensions)photoDimensions {
    return [objc_getAssociatedObject(self, CamRelayResolvedDimensionsKey) CMVideoDimensionsValue];
}
- (CMVideoDimensions)rawPhotoDimensions { return (CMVideoDimensions){0, 0}; }
- (CMVideoDimensions)previewDimensions { return (CMVideoDimensions){0, 0}; }
- (CMVideoDimensions)embeddedThumbnailDimensions { return (CMVideoDimensions){0, 0}; }
- (BOOL)isFlashEnabled { return NO; }
- (BOOL)isRedEyeReductionEnabled { return NO; }
- (NSUInteger)expectedPhotoCount { return 1; }
- (CMTimeRange)photoProcessingTimeRange { return CMTimeRangeMake(kCMTimeZero, kCMTimeZero); }
@end

@interface CamRelaySyntheticPhoto : AVCapturePhoto
@end

@implementation CamRelaySyntheticPhoto
- (CMTime)timestamp { return [objc_getAssociatedObject(self, CamRelayPhotoTimestampKey) CMTimeValue]; }
- (BOOL)isRawPhoto { return NO; }
- (CVPixelBufferRef)pixelBuffer {
    return (__bridge CVPixelBufferRef)objc_getAssociatedObject(self, CamRelayPhotoPixelBufferKey);
}
- (CVPixelBufferRef)previewPixelBuffer { return NULL; }
- (NSDictionary *)embeddedThumbnailPhotoFormat { return nil; }
- (AVDepthData *)depthData { return nil; }
- (AVPortraitEffectsMatte *)portraitEffectsMatte { return nil; }
- (AVCameraCalibrationData *)cameraCalibrationData { return nil; }
- (AVSemanticSegmentationMatte *)semanticSegmentationMatteForType:(AVSemanticSegmentationMatteType)type {
    return nil;
}
- (NSDictionary<NSString *, id> *)metadata {
    CVPixelBufferRef pixels = self.pixelBuffer;
    if (pixels == NULL) { return @{}; }
    NSNumber *width = @(CVPixelBufferGetWidth(pixels));
    NSNumber *height = @(CVPixelBufferGetHeight(pixels));
    return @{
        (__bridge NSString *)kCGImagePropertyPixelWidth: width,
        (__bridge NSString *)kCGImagePropertyPixelHeight: height,
        (__bridge NSString *)kCGImagePropertyOrientation: @1,
        (__bridge NSString *)kCGImagePropertyExifDictionary: @{
            (__bridge NSString *)kCGImagePropertyExifPixelXDimension: width,
            (__bridge NSString *)kCGImagePropertyExifPixelYDimension: height,
        },
    };
}
- (AVCaptureResolvedPhotoSettings *)resolvedSettings {
    return objc_getAssociatedObject(self, CamRelayPhotoResolvedSettingsKey);
}
- (NSInteger)photoCount { return 1; }
- (AVCaptureDeviceType)sourceDeviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (NSData *)fileDataRepresentation { return objc_getAssociatedObject(self, CamRelayPhotoDataKey); }
- (NSData *)fileDataRepresentationWithCustomizer:(id<AVCapturePhotoFileDataRepresentationCustomizer>)customizer {
    NSDictionary *metadata = self.metadata;
    if ([customizer respondsToSelector:@selector(replacementMetadataForPhoto:)]) {
        metadata = [customizer replacementMetadataForPhoto:self];
    }
    // Synthetic photos have no auxiliary images. Reject requested replacements
    // that cannot be represented, rather than silently discarding client data.
    if ([customizer respondsToSelector:@selector(replacementEmbeddedThumbnailPixelBufferWithPhotoFormat:forPhoto:)]) {
        NSDictionary *format = nil;
        if ([customizer replacementEmbeddedThumbnailPixelBufferWithPhotoFormat:&format forPhoto:self] != NULL) {
            return nil;
        }
    }
    if ([customizer respondsToSelector:@selector(replacementDepthDataForPhoto:)] &&
        [customizer replacementDepthDataForPhoto:self] != nil) { return nil; }
    if ([customizer respondsToSelector:@selector(replacementPortraitEffectsMatteForPhoto:)] &&
        [customizer replacementPortraitEffectsMatteForPhoto:self] != nil) { return nil; }

    CGImageRef image = self.CGImageRepresentation;
    if (image == NULL) { return nil; }
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)data, CFSTR("public.jpeg"), 1, NULL
    );
    if (destination == NULL) { return nil; }
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)metadata);
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return success ? data : nil;
}
- (CGImageRef)CGImageRepresentation {
    CVPixelBufferRef pixelBuffer = self.pixelBuffer;
    if (pixelBuffer == NULL) {
        return NULL;
    }
    CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CGImageRef cgImage = [CamRelayImageContext() createCGImage:image fromRect:image.extent];
    if (cgImage == NULL) {
        return NULL;
    }
    objc_setAssociatedObject(
        self,
        CamRelayPhotoCGImageKey,
        (__bridge id)cgImage,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    CGImageRelease(cgImage);
    return (__bridge CGImageRef)objc_getAssociatedObject(self, CamRelayPhotoCGImageKey);
}
@end

@interface CamRelayPhotoRequest : NSObject
@property(nonatomic, strong) AVCapturePhotoOutput *output;
@property(nonatomic, strong) AVCapturePhotoSettings *settings;
@property(nonatomic, strong) id<AVCapturePhotoCaptureDelegate> delegate;
@end

@implementation CamRelayPhotoRequest
@end

static NSData *CamRelayJPEGData(CVPixelBufferRef pixelBuffer) {
    CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSData *data = [CamRelayImageContext() JPEGRepresentationOfImage:image
                                                         colorSpace:colorSpace
                                                            options:@{}];
    CGColorSpaceRelease(colorSpace);
    return data;
}

static AVCaptureResolvedPhotoSettings *CamRelayResolvedPhotoSettings(
    AVCapturePhotoSettings *settings,
    CVPixelBufferRef pixelBuffer
) {
    AVCaptureResolvedPhotoSettings *resolved =
        class_createInstance(CamRelaySyntheticResolvedPhotoSettings.class, 0);
    CMVideoDimensions dimensions = {
        (int32_t)CVPixelBufferGetWidth(pixelBuffer),
        (int32_t)CVPixelBufferGetHeight(pixelBuffer),
    };
    objc_setAssociatedObject(
        resolved,
        CamRelayResolvedUniqueIDKey,
        @(settings.uniqueID),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        resolved,
        CamRelayResolvedDimensionsKey,
        [NSValue valueWithCMVideoDimensions:dimensions],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    return resolved;
}

static void CamRelayDeliverPhotoRequest(CamRelayPhotoRequest *request, CMSampleBufferRef sampleBuffer) {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer == NULL) {
        return;
    }

    AVCaptureResolvedPhotoSettings *resolved =
        CamRelayResolvedPhotoSettings(request.settings, pixelBuffer);
    id<AVCapturePhotoCaptureDelegate> delegate = request.delegate;
    if ([delegate respondsToSelector:@selector(captureOutput:willBeginCaptureForResolvedSettings:)]) {
        [delegate captureOutput:request.output willBeginCaptureForResolvedSettings:resolved];
    }
    if ([delegate respondsToSelector:@selector(captureOutput:willCapturePhotoForResolvedSettings:)]) {
        [delegate captureOutput:request.output willCapturePhotoForResolvedSettings:resolved];
    }
    if ([delegate respondsToSelector:@selector(captureOutput:didCapturePhotoForResolvedSettings:)]) {
        [delegate captureOutput:request.output didCapturePhotoForResolvedSettings:resolved];
    }

    if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
        AVCapturePhoto *photo = class_createInstance(CamRelaySyntheticPhoto.class, 0);
        objc_setAssociatedObject(
            photo,
            CamRelayPhotoPixelBufferKey,
            (__bridge id)pixelBuffer,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        objc_setAssociatedObject(
            photo,
            CamRelayPhotoDataKey,
            CamRelayJPEGData(pixelBuffer),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        objc_setAssociatedObject(
            photo,
            CamRelayPhotoResolvedSettingsKey,
            resolved,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        objc_setAssociatedObject(
            photo,
            CamRelayPhotoTimestampKey,
            [NSValue valueWithCMTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        [delegate captureOutput:request.output didFinishProcessingPhoto:photo error:nil];
    } else if ([delegate respondsToSelector:
        @selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [delegate captureOutput:request.output
            didFinishProcessingPhotoSampleBuffer:sampleBuffer
            previewPhotoSampleBuffer:NULL
            resolvedSettings:resolved
            bracketSettings:nil
            error:nil];
#pragma clang diagnostic pop
    }

    if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
        [delegate captureOutput:request.output didFinishCaptureForResolvedSettings:resolved error:nil];
    }
}

@interface CamRelaySyntheticMachineReadableCode : AVMetadataMachineReadableCodeObject
@end

@implementation CamRelaySyntheticMachineReadableCode
- (AVMetadataObjectType)type { return AVMetadataObjectTypeQRCode; }
- (NSString *)stringValue { return objc_getAssociatedObject(self, CamRelayMetadataStringKey); }
- (CGRect)bounds {
    NSValue *value = objc_getAssociatedObject(self, CamRelayMetadataBoundsKey);
    CGRect bounds = CGRectZero;
    if (value != nil) {
        [value getValue:&bounds size:sizeof(bounds)];
    }
    return bounds;
}
- (CMTime)time { return [objc_getAssociatedObject(self, CamRelayMetadataTimeKey) CMTimeValue]; }
- (CMTime)duration { return kCMTimeZero; }
- (NSArray *)corners { return objc_getAssociatedObject(self, CamRelayMetadataCornersKey) ?: @[]; }
@end

static NSValue *CamRelayValueWithRect(CGRect rect) {
    return [NSValue value:&rect withObjCType:@encode(CGRect)];
}

static NSArray<AVMetadataObject *> *CamRelayMetadataObjects(CMSampleBufferRef sampleBuffer) {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer == NULL) {
        return @[];
    }
    static CIDetector *detector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        detector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                      context:CamRelayImageContext()
                                      options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
    });
    CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    NSArray<CIFeature *> *features = [detector featuresInImage:image];
    NSMutableArray<AVMetadataObject *> *objects = [NSMutableArray array];
    CGFloat width = CGRectGetWidth(image.extent);
    CGFloat height = CGRectGetHeight(image.extent);
    for (CIFeature *feature in features) {
        if (![feature isKindOfClass:CIQRCodeFeature.class]) {
            continue;
        }
        CIQRCodeFeature *code = (CIQRCodeFeature *)feature;
        CamRelaySyntheticMachineReadableCode *object =
            class_createInstance(CamRelaySyntheticMachineReadableCode.class, 0);
        CGRect featureBounds = code.bounds;
        CGRect normalizedBounds = CGRectMake(
            CGRectGetMinX(featureBounds) / width,
            1.0 - CGRectGetMaxY(featureBounds) / height,
            CGRectGetWidth(featureBounds) / width,
            CGRectGetHeight(featureBounds) / height
        );
        NSArray *corners = @[
            CamRelayValueWithPoint(CGPointMake(code.topLeft.x / width, 1.0 - code.topLeft.y / height)),
            CamRelayValueWithPoint(CGPointMake(code.topRight.x / width, 1.0 - code.topRight.y / height)),
            CamRelayValueWithPoint(CGPointMake(code.bottomRight.x / width, 1.0 - code.bottomRight.y / height)),
            CamRelayValueWithPoint(CGPointMake(code.bottomLeft.x / width, 1.0 - code.bottomLeft.y / height)),
        ];
        objc_setAssociatedObject(
            object,
            CamRelayMetadataStringKey,
            code.messageString,
            OBJC_ASSOCIATION_COPY_NONATOMIC
        );
        objc_setAssociatedObject(
            object,
            CamRelayMetadataBoundsKey,
            CamRelayValueWithRect(normalizedBounds),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        objc_setAssociatedObject(
            object,
            CamRelayMetadataTimeKey,
            [NSValue valueWithCMTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        objc_setAssociatedObject(
            object,
            CamRelayMetadataCornersKey,
            corners,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        [objects addObject:object];
    }
    return objects;
}

@interface CamRelayMovieRecorder : NSObject
@property(nonatomic, weak) AVCaptureMovieFileOutput *output;
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, strong) id<AVCaptureFileOutputRecordingDelegate> delegate;
@property(nonatomic, strong) AVAssetWriter *writer;
@property(nonatomic, strong) AVAssetWriterInput *writerInput;
@property(nonatomic) BOOL recording;
@property(nonatomic) BOOL paused;
@property(nonatomic) BOOL delegateStarted;
@property(nonatomic) CMTime startTime;
@property(nonatomic) CMTime lastTime;
- (void)startAtURL:(NSURL *)url delegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate;
- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)stop;
@end

@implementation CamRelayMovieRecorder

- (NSArray<AVCaptureConnection *> *)connections {
    return self.output.connections ?: @[];
}

- (void)startAtURL:(NSURL *)url delegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    @synchronized(self) {
        self.url = url;
        self.delegate = delegate;
        self.recording = YES;
        self.paused = NO;
        self.delegateStarted = NO;
        self.startTime = kCMTimeInvalid;
        self.lastTime = kCMTimeInvalid;
    }
}

- (BOOL)prepareWriterForSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError **)outError {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer == NULL) {
        return NO;
    }
    AVFileType fileType = [self.url.pathExtension.lowercaseString isEqualToString:@"mp4"]
        ? AVFileTypeMPEG4
        : AVFileTypeQuickTimeMovie;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:self.url fileType:fileType error:outError];
    if (writer == nil) {
        return NO;
    }
    NSDictionary *configuredSettings = objc_getAssociatedObject(self.output, CamRelayMovieOutputSettingsKey);
    NSDictionary *settings = configuredSettings ?: @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(CVPixelBufferGetWidth(pixelBuffer)),
        AVVideoHeightKey: @(CVPixelBufferGetHeight(pixelBuffer)),
    };
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                   outputSettings:settings];
    input.expectsMediaDataInRealTime = YES;
    if (![writer canAddInput:input]) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:@"CamRelayRuntime" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"Could not configure movie recording for the synthetic camera."
            }];
        }
        return NO;
    }
    [writer addInput:input];
    if (![writer startWriting]) {
        if (outError != NULL) {
            *outError = writer.error;
        }
        return NO;
    }
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    [writer startSessionAtSourceTime:timestamp];
    self.writer = writer;
    self.writerInput = input;
    self.startTime = timestamp;
    return YES;
}

- (void)finishWithError:(NSError *)error {
    id<AVCaptureFileOutputRecordingDelegate> delegate = self.delegate;
    NSURL *url = self.url;
    AVCaptureMovieFileOutput *output = self.output;
    NSArray *connections = self.connections;
    self.recording = NO;
    self.paused = NO;
    self.writer = nil;
    self.writerInput = nil;
    self.delegate = nil;
    if (delegate != nil) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [delegate captureOutput:output
                didFinishRecordingToOutputFileAtURL:url
                fromConnections:connections
                error:error];
        });
    }
}

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    @synchronized(self) {
        if (!self.recording || self.paused) {
            return;
        }
        if (self.writer == nil) {
            NSError *error = nil;
            if (![self prepareWriterForSampleBuffer:sampleBuffer error:&error]) {
                [self finishWithError:error];
                return;
            }
        }
        if (!self.delegateStarted) {
            self.delegateStarted = YES;
            id<AVCaptureFileOutputRecordingDelegate> delegate = self.delegate;
            if ([delegate respondsToSelector:
                @selector(captureOutput:didStartRecordingToOutputFileAtURL:fromConnections:)]) {
                [delegate captureOutput:self.output
                    didStartRecordingToOutputFileAtURL:self.url
                    fromConnections:self.connections];
            }
        }
        if (self.writerInput.readyForMoreMediaData) {
            if (![self.writerInput appendSampleBuffer:sampleBuffer]) {
                [self finishWithError:self.writer.error];
                return;
            }
            self.lastTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        }
    }
}

- (void)stop {
    @synchronized(self) {
        if (!self.recording) {
            return;
        }
        self.recording = NO;
        if (self.writer == nil) {
            NSError *error = [NSError errorWithDomain:@"CamRelayRuntime" code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"Movie recording stopped before a camera frame was available."
            }];
            [self finishWithError:error];
            return;
        }
        [self.writerInput markAsFinished];
        AVAssetWriter *writer = self.writer;
        [writer finishWritingWithCompletionHandler:^{
            [self finishWithError:writer.error];
        }];
    }
}

@end

@interface CamRelayFrameEmitter : NSObject
@property(nonatomic, weak) AVCaptureSession *session;
@property(nonatomic) dispatch_queue_t receiverQueue;
@property(nonatomic) int socketDescriptor;
@property(nonatomic) BOOL stopped;
@property(nonatomic) int64_t frameNumber;
@property(atomic) uint64_t generation;
- (void)startWithSession:(AVCaptureSession *)session;
- (void)stop;
@end

@implementation CamRelayFrameEmitter

- (void)startWithSession:(AVCaptureSession *)session {
    @synchronized(self) {
        if (self.receiverQueue != nil) {
            return;
        }
        self.session = session;
        self.socketDescriptor = -1;
        self.stopped = NO;
        self.receiverQueue = dispatch_queue_create("org.camrelay.runtime.receiver", DISPATCH_QUEUE_SERIAL);
    }
    __weak CamRelayFrameEmitter *weakSelf = self;
    dispatch_async(self.receiverQueue, ^{
        [weakSelf receiveFrames];
    });
}

- (void)receiveFrames {
    const char *portValue = getenv("CAMRELAY_PORT");
    int port = portValue == NULL ? 0 : atoi(portValue);
    if (port <= 0 || port > UINT16_MAX) {
        NSLog(@"[CamRelayRuntime] invalid frame server port");
        return;
    }

    while (![self isStopped] && CamRelayIsActive()) {
        @autoreleasepool {
            int descriptor = CamRelayConnectToFrameServer();
            if (descriptor < 0 || !CamRelaySendClientRole(descriptor, CamRelayFrameClientRole)) {
                if (descriptor >= 0) {
                    close(descriptor);
                }
                usleep(100000);
                continue;
            }
            @synchronized(self) {
                self.socketDescriptor = descriptor;
            }
            NSLog(@"[CamRelayRuntime] connected to frame server");
            [self readFrameStream:descriptor];
            close(descriptor);
            @synchronized(self) {
                if (self.socketDescriptor == descriptor) {
                    self.socketDescriptor = -1;
                }
            }
        }
    }
    if (![self isStopped]) {
        AVCaptureSession *session = self.session;
        @synchronized(self) {
            self.stopped = YES;
        }
        if (session != nil) {
            objc_setAssociatedObject(session, CamRelayRunningKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [[NSNotificationCenter defaultCenter]
                postNotificationName:AVCaptureSessionDidStopRunningNotification
                              object:session];
        }
    }
}

- (void)readFrameStream:(int)descriptor {
    uint32_t header[5] = {0};
    if (![self readExactly:header byteCount:sizeof(header) from:descriptor]) {
        return;
    }
    uint32_t magic = ntohl(header[0]);
    size_t width = ntohl(header[1]);
    size_t height = ntohl(header[2]);
    size_t bytesPerRow = ntohl(header[3]);
    int32_t framesPerSecond = (int32_t)ntohl(header[4]);
    if (magic != 0x43524633 || width == 0 || height == 0 ||
        width > 4096 || height > 4096 || bytesPerRow < width * 4 ||
        framesPerSecond <= 0 || framesPerSecond > 120) {
        NSLog(@"[CamRelayRuntime] rejected invalid frame stream header");
        return;
    }

    size_t frameByteCount = bytesPerRow * height;
    uint8_t *frameBytes = malloc(frameByteCount);
    if (frameBytes == NULL) {
        return;
    }
    uint64_t acknowledgedGeneration = 0;
    while (![self isStopped]) {
        uint64_t frameHeader[3] = {0};
        if (![self readExactly:frameHeader byteCount:sizeof(frameHeader) from:descriptor]) {
            break;
        }
        uint64_t generation = CFSwapInt64BigToHost(frameHeader[0]);
        uint64_t presentationTimeNanoseconds = CFSwapInt64BigToHost(frameHeader[1]);
        uint64_t durationNanoseconds = CFSwapInt64BigToHost(frameHeader[2]);
        if (generation == 0 || generation < self.generation ||
            presentationTimeNanoseconds > INT64_MAX || durationNanoseconds == 0 ||
            durationNanoseconds > INT64_MAX ||
            ![self readExactly:frameBytes byteCount:frameByteCount from:descriptor]) {
            NSLog(@"[CamRelayRuntime] rejected invalid frame metadata");
            break;
        }
        @autoreleasepool {
            CMSampleBufferRef sampleBuffer = CamRelayCreateFrame(
                frameBytes,
                width,
                height,
                bytesPerRow,
                presentationTimeNanoseconds,
                durationNanoseconds
            );
            self.frameNumber += 1;
            if (sampleBuffer == NULL) {
                continue;
            }
            BOOL changed = self.generation != generation;
            self.generation = generation;
            [self deliverSampleBuffer:sampleBuffer resetPreview:changed];
            CFRelease(sampleBuffer);
            if (acknowledgedGeneration != generation) {
                uint64_t acknowledgement = CFSwapInt64HostToBig(generation);
                const uint8_t *bytes = (const uint8_t *)&acknowledgement;
                size_t remaining = sizeof(acknowledgement);
                while (remaining > 0) {
                    ssize_t count = send(descriptor, bytes, remaining, 0);
                    if (count < 0 && errno == EINTR) { continue; }
                    if (count <= 0) { free(frameBytes); return; }
                    remaining -= (size_t)count;
                    bytes += count;
                }
                acknowledgedGeneration = generation;
            }
        }
    }
    free(frameBytes);
}

- (void)deliverSampleBuffer:(CMSampleBufferRef)sampleBuffer resetPreview:(BOOL)resetPreview {
    AVCaptureSession *session = self.session;
    uint64_t generation = self.generation;
    if (session == nil) {
        return;
    }
    objc_setAssociatedObject(
        session,
        CamRelayLatestSampleBufferKey,
        (__bridge id)sampleBuffer,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    NSArray *outputs = [CamRelayMutableArray(session, CamRelaySyntheticOutputsKey) copy];
    for (AVCaptureOutput *output in outputs) {
        AVCaptureConnection *connection = objc_getAssociatedObject(output, CamRelayOutputConnectionKey);
        if (connection != nil && !connection.isEnabled) {
            continue;
        }
        if ([output isKindOfClass:AVCaptureVideoDataOutput.class]) {
            AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
            id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = videoOutput.sampleBufferDelegate;
            dispatch_queue_t callbackQueue = videoOutput.sampleBufferCallbackQueue;
            if (delegate == nil || callbackQueue == nil) {
                continue;
            }
            CMSampleBufferRef outputSample =
                CamRelayCopySampleForVideoOutput(sampleBuffer, videoOutput, connection);
            if (outputSample == NULL) {
                continue;
            }
            dispatch_async(callbackQueue, ^{
                if (self.generation == generation && ![self isStopped]) {
                    [delegate captureOutput:videoOutput
                        didOutputSampleBuffer:outputSample
                        fromConnection:connection];
                }
                CFRelease(outputSample);
            });
        } else if ([output isKindOfClass:AVCaptureMovieFileOutput.class]) {
            CamRelayMovieRecorder *recorder = objc_getAssociatedObject(output, CamRelayMovieRecorderKey);
            [recorder appendSampleBuffer:sampleBuffer];
        } else if ([output isKindOfClass:AVCaptureMetadataOutput.class] && self.frameNumber % 5 == 0) {
            AVCaptureMetadataOutput *metadataOutput = (AVCaptureMetadataOutput *)output;
            if (![metadataOutput.metadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
                continue;
            }
            id<AVCaptureMetadataOutputObjectsDelegate> delegate = metadataOutput.metadataObjectsDelegate;
            dispatch_queue_t callbackQueue = metadataOutput.metadataObjectsCallbackQueue;
            if (delegate == nil || callbackQueue == nil) {
                continue;
            }
            NSArray<AVMetadataObject *> *objects = CamRelayMetadataObjects(sampleBuffer);
            if (objects.count > 0) {
                dispatch_async(callbackQueue, ^{
                    if (self.generation == generation && ![self isStopped]) {
                        [delegate captureOutput:metadataOutput
                            didOutputMetadataObjects:objects
                            fromConnection:connection];
                    }
                });
            }
        }
    }

    NSMutableArray *photoRequests = CamRelayMutableArray(session, CamRelayPhotoRequestsKey);
    NSArray *requests = nil;
    @synchronized(photoRequests) {
        requests = [photoRequests copy];
        [photoRequests removeAllObjects];
    }
    for (CamRelayPhotoRequest *request in requests) {
        CFRetain(sampleBuffer);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            CamRelayDeliverPhotoRequest(request, sampleBuffer);
            CFRelease(sampleBuffer);
        });
    }

    NSHashTable *previewLayers = objc_getAssociatedObject(session, CamRelayPreviewLayersKey);
    NSArray *layers = previewLayers.allObjects;
    if (layers.count > 0) {
        CMSampleBufferRef previewSample = NULL;
        if (CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &previewSample) == noErr &&
            previewSample != NULL) {
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(previewSample, YES);
            if (attachments != NULL && CFArrayGetCount(attachments) > 0) {
                CFMutableDictionaryRef attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(
                    attachments,
                    0
                );
                CFDictionarySetValue(
                    attachment,
                    kCMSampleAttachmentKey_DisplayImmediately,
                    kCFBooleanTrue
                );
            }
            for (AVCaptureVideoPreviewLayer *layer in layers) {
                AVCaptureConnection *connection = objc_getAssociatedObject(
                    layer,
                    CamRelayPreviewConnectionKey
                );
                if (connection != nil && !connection.isEnabled) {
                    continue;
                }
                AVSampleBufferDisplayLayer *displayLayer = objc_getAssociatedObject(
                    layer,
                    CamRelayPreviewDisplayLayerKey
                );
                dispatch_async(dispatch_get_main_queue(), ^{
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    displayLayer.frame = layer.bounds;
                    displayLayer.videoGravity = layer.videoGravity;
                    [CATransaction commit];
                });
                AVSampleBufferVideoRenderer *renderer = displayLayer.sampleBufferRenderer;
                if (resetPreview || renderer.status == AVQueuedSampleBufferRenderingStatusFailed) {
                    [renderer flush];
                }
                if (renderer.isReadyForMoreMediaData) {
                    [renderer enqueueSampleBuffer:previewSample];
                }
            }
            CFRelease(previewSample);
        }
    }
}

- (BOOL)readExactly:(void *)buffer byteCount:(size_t)byteCount from:(int)descriptor {
    uint8_t *cursor = buffer;
    size_t remaining = byteCount;
    while (remaining > 0 && ![self isStopped]) {
        ssize_t count = recv(descriptor, cursor, remaining, 0);
        if (count <= 0) {
            return NO;
        }
        cursor += count;
        remaining -= (size_t)count;
    }
    return remaining == 0;
}

- (BOOL)isStopped {
    @synchronized(self) {
        return self.stopped;
    }
}

- (void)stop {
    int descriptor = -1;
    @synchronized(self) {
        self.stopped = YES;
        descriptor = self.socketDescriptor;
        self.socketDescriptor = -1;
    }
    if (descriptor >= 0) {
        shutdown(descriptor, SHUT_RDWR);
    }
    self.session = nil;
}

@end

static NSArray<AVCaptureDevice *> *(*OriginalDiscoveryDevices)(id, SEL);
static id (*OriginalDiscoverySessionFactory)(
    id, SEL, NSArray<AVCaptureDeviceType> *, AVMediaType, AVCaptureDevicePosition
);
static id CamRelayDiscoverySessionFactory(
    id self,
    SEL selector,
    NSArray<AVCaptureDeviceType> *deviceTypes,
    AVMediaType mediaType,
    AVCaptureDevicePosition position
) {
    id session = OriginalDiscoverySessionFactory(self, selector, deviceTypes, mediaType, position);
    objc_setAssociatedObject(
        session,
        CamRelayDiscoveryDeviceTypesKey,
        deviceTypes,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        session,
        CamRelayDiscoveryMediaTypeKey,
        mediaType,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        session,
        CamRelayDiscoveryPositionKey,
        @(position),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    return session;
}

static NSArray<AVCaptureDevice *> *CamRelayDiscoveryDevices(id self, SEL selector) {
    if (!CamRelayIsActive() || CamRelayIsConstructingCaptureOutput()) {
        return OriginalDiscoveryDevices(self, selector);
    }
    AVMediaType mediaType = objc_getAssociatedObject(self, CamRelayDiscoveryMediaTypeKey);
    if (mediaType != nil && ![mediaType isEqualToString:AVMediaTypeVideo]) {
        return OriginalDiscoveryDevices(self, selector);
    }
    NSArray<AVCaptureDeviceType> *deviceTypes =
        objc_getAssociatedObject(self, CamRelayDiscoveryDeviceTypesKey);
    if (deviceTypes.count > 0 &&
        ![deviceTypes containsObject:AVCaptureDeviceTypeBuiltInWideAngleCamera]) {
        return @[];
    }
    AVCaptureDevicePosition position =
        (AVCaptureDevicePosition)[objc_getAssociatedObject(self, CamRelayDiscoveryPositionKey) integerValue];
    return CamRelayVideoDevicesForPosition(position);
}

static NSArray<AVCaptureDevice *> *(*OriginalDevicesWithMediaType)(id, SEL, AVMediaType);
static NSArray<AVCaptureDevice *> *CamRelayDevicesWithMediaType(
    id self,
    SEL selector,
    AVMediaType mediaType
) {
    if (!CamRelayIsActive() || CamRelayIsConstructingCaptureOutput()) {
        return OriginalDevicesWithMediaType(self, selector, mediaType);
    }
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        return CamRelayVideoDevicesForPosition(AVCaptureDevicePositionUnspecified);
    }
    return OriginalDevicesWithMediaType(self, selector, mediaType);
}

static AVCaptureDevice *(*OriginalDeviceWithUniqueID)(id, SEL, NSString *);
static AVCaptureDevice *CamRelayDeviceWithUniqueID(
    id self,
    SEL selector,
    NSString *uniqueID
) {
    if (CamRelayIsActive() && !CamRelayIsConstructingCaptureOutput()) {
        if ([uniqueID isEqualToString:@"org.camrelay.synthetic.front"]) {
            return CamRelayDevice(AVCaptureDevicePositionFront);
        }
        if ([uniqueID isEqualToString:@"org.camrelay.synthetic.back"]) {
            return CamRelayDevice(AVCaptureDevicePositionBack);
        }
    }
    return OriginalDeviceWithUniqueID(self, selector, uniqueID);
}

static AVCaptureDevice *(*OriginalDefaultDeviceWithMediaType)(id, SEL, AVMediaType);
static AVCaptureDevice *CamRelayDefaultDeviceWithMediaType(
    id self,
    SEL selector,
    AVMediaType mediaType
) {
    if (!CamRelayIsActive() || CamRelayIsConstructingCaptureOutput()) {
        return OriginalDefaultDeviceWithMediaType(self, selector, mediaType);
    }
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        return CamRelayDevice(AVCaptureDevicePositionBack);
    }
    return OriginalDefaultDeviceWithMediaType(self, selector, mediaType);
}

static AVCaptureDevice *(*OriginalDefaultDeviceWithType)(
    id, SEL, AVCaptureDeviceType, AVMediaType, AVCaptureDevicePosition
);
static AVCaptureDevice *CamRelayDefaultDeviceWithType(
    id self,
    SEL selector,
    AVCaptureDeviceType deviceType,
    AVMediaType mediaType,
    AVCaptureDevicePosition position
) {
    if (!CamRelayIsActive() || CamRelayIsConstructingCaptureOutput()) {
        return OriginalDefaultDeviceWithType(self, selector, deviceType, mediaType, position);
    }
    if ((mediaType == nil || [mediaType isEqualToString:AVMediaTypeVideo]) &&
        [deviceType isEqualToString:AVCaptureDeviceTypeBuiltInWideAngleCamera]) {
        AVCaptureDevicePosition resolved = position == AVCaptureDevicePositionFront
            ? AVCaptureDevicePositionFront
            : AVCaptureDevicePositionBack;
        return CamRelayDevice(resolved);
    }
    return OriginalDefaultDeviceWithType(self, selector, deviceType, mediaType, position);
}

static AVAuthorizationStatus (*OriginalAuthorizationStatus)(id, SEL, AVMediaType);
static AVAuthorizationStatus CamRelayAuthorizationStatus(id self, SEL selector, AVMediaType mediaType) {
    if (CamRelayIsActive() && [mediaType isEqualToString:AVMediaTypeVideo]) {
        return AVAuthorizationStatusAuthorized;
    }
    return OriginalAuthorizationStatus(self, selector, mediaType);
}

static void (*OriginalRequestAccess)(id, SEL, AVMediaType, void (^)(BOOL));
static void CamRelayRequestAccess(
    id self,
    SEL selector,
    AVMediaType mediaType,
    void (^handler)(BOOL)
) {
    if (CamRelayIsActive() && [mediaType isEqualToString:AVMediaTypeVideo]) {
        if (handler != nil) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                handler(YES);
            });
        }
        return;
    }
    OriginalRequestAccess(self, selector, mediaType, handler);
}

static id (*OriginalDeviceInputInitializer)(id, SEL, AVCaptureDevice *, NSError **);
static id CamRelayDeviceInputInitializer(
    id self,
    SEL selector,
    AVCaptureDevice *device,
    NSError **outError
) {
    if ([device isKindOfClass:CamRelaySyntheticDevice.class]) {
        object_setClass(self, CamRelaySyntheticDeviceInput.class);
        objc_setAssociatedObject(self, CamRelayInputDeviceKey, device, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (outError != NULL) {
            *outError = nil;
        }
        return self;
    }
    return OriginalDeviceInputInitializer(self, selector, device, outError);
}

static NSArray<AVCaptureInput *> *(*OriginalSessionInputs)(AVCaptureSession *, SEL);
static NSArray<AVCaptureInput *> *CamRelaySessionInputs(AVCaptureSession *session, SEL selector) {
    if ([objc_getAssociatedObject(session, CamRelayCommittingConfigurationKey) boolValue]) {
        return OriginalSessionInputs(session, selector);
    }
    return [OriginalSessionInputs(session, selector)
        arrayByAddingObjectsFromArray:CamRelayMutableArray(session, CamRelaySyntheticInputsKey)];
}

static NSArray<AVCaptureOutput *> *(*OriginalSessionOutputs)(AVCaptureSession *, SEL);
static NSArray<AVCaptureOutput *> *CamRelaySessionOutputs(AVCaptureSession *session, SEL selector) {
    if ([objc_getAssociatedObject(session, CamRelayCommittingConfigurationKey) boolValue]) {
        return OriginalSessionOutputs(session, selector);
    }
    return [OriginalSessionOutputs(session, selector)
        arrayByAddingObjectsFromArray:CamRelayMutableArray(session, CamRelaySyntheticOutputsKey)];
}

static NSArray<AVCaptureConnection *> *(*OriginalSessionConnections)(AVCaptureSession *, SEL);
static NSArray<AVCaptureConnection *> *CamRelaySessionConnections(AVCaptureSession *session, SEL selector) {
    if ([objc_getAssociatedObject(session, CamRelayCommittingConfigurationKey) boolValue]) {
        return OriginalSessionConnections(session, selector);
    }
    return [OriginalSessionConnections(session, selector)
        arrayByAddingObjectsFromArray:CamRelayMutableArray(session, CamRelaySyntheticConnectionsKey)];
}

static BOOL (*OriginalCanSetSessionPreset)(AVCaptureSession *, SEL, AVCaptureSessionPreset);
static BOOL CamRelayCanSetSessionPreset(
    AVCaptureSession *session,
    SEL selector,
    AVCaptureSessionPreset preset
) {
    return CamRelaySessionUsesSyntheticCamera(session)
        ? YES
        : OriginalCanSetSessionPreset(session, selector, preset);
}

static void (*OriginalCommitConfiguration)(AVCaptureSession *, SEL);
static void CamRelayCommitConfiguration(AVCaptureSession *session, SEL selector) {
    if (!CamRelaySessionUsesSyntheticCamera(session)) {
        OriginalCommitConfiguration(session, selector);
        return;
    }
    objc_setAssociatedObject(
        session,
        CamRelayCommittingConfigurationKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    OriginalCommitConfiguration(session, selector);
    objc_setAssociatedObject(
        session,
        CamRelayCommittingConfigurationKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static AVCaptureSessionPreset (*OriginalSessionPreset)(AVCaptureSession *, SEL);
static AVCaptureSessionPreset CamRelaySessionPreset(AVCaptureSession *session, SEL selector) {
    return objc_getAssociatedObject(session, CamRelaySessionPresetKey)
        ?: OriginalSessionPreset(session, selector);
}

static void (*OriginalSetSessionPreset)(AVCaptureSession *, SEL, AVCaptureSessionPreset);
static void CamRelaySetSessionPreset(
    AVCaptureSession *session,
    SEL selector,
    AVCaptureSessionPreset preset
) {
    if (CamRelaySessionUsesSyntheticCamera(session)) {
        objc_setAssociatedObject(session, CamRelaySessionPresetKey, preset, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    OriginalSetSessionPreset(session, selector, preset);
}

static BOOL (*OriginalCanAddInput)(AVCaptureSession *, SEL, AVCaptureInput *);
static BOOL CamRelayCanAddInput(AVCaptureSession *session, SEL selector, AVCaptureInput *input) {
    if ([input isKindOfClass:CamRelaySyntheticDeviceInput.class]) {
        return YES;
    }
    return OriginalCanAddInput(session, selector, input);
}

static void CamRelayStoreSyntheticInput(AVCaptureSession *session, AVCaptureInput *input, BOOL connect) {
    NSMutableArray *inputs = CamRelayMutableArray(session, CamRelaySyntheticInputsKey);
    if (![inputs containsObject:input]) {
        [inputs addObject:input];
    }
    if (connect) {
        for (AVCaptureOutput *output in CamRelayMutableArray(session, CamRelaySyntheticOutputsKey)) {
            CamRelayEnsureOutputConnection(session, output);
        }
        NSHashTable *previewLayers = objc_getAssociatedObject(session, CamRelayPreviewLayersKey);
        for (AVCaptureVideoPreviewLayer *layer in previewLayers.allObjects) {
            CamRelayRegisterPreviewLayer(layer, session, YES);
        }
    }
}

static void (*OriginalAddInput)(AVCaptureSession *, SEL, AVCaptureInput *);
static void CamRelayAddInput(AVCaptureSession *session, SEL selector, AVCaptureInput *input) {
    if ([input isKindOfClass:CamRelaySyntheticDeviceInput.class]) {
        CamRelayStoreSyntheticInput(session, input, YES);
        return;
    }
    OriginalAddInput(session, selector, input);
}

static void (*OriginalAddInputWithNoConnections)(AVCaptureSession *, SEL, AVCaptureInput *);
static void CamRelayAddInputWithNoConnections(
    AVCaptureSession *session,
    SEL selector,
    AVCaptureInput *input
) {
    if ([input isKindOfClass:CamRelaySyntheticDeviceInput.class]) {
        CamRelayStoreSyntheticInput(session, input, NO);
        return;
    }
    OriginalAddInputWithNoConnections(session, selector, input);
}

static void (*OriginalRemoveInput)(AVCaptureSession *, SEL, AVCaptureInput *);
static void CamRelayRemoveInput(AVCaptureSession *session, SEL selector, AVCaptureInput *input) {
    if ([input isKindOfClass:CamRelaySyntheticDeviceInput.class]) {
        NSMutableArray *connections = CamRelayMutableArray(session, CamRelaySyntheticConnectionsKey);
        for (AVCaptureConnection *connection in connections.copy) {
            BOOL usesInput = NO;
            for (AVCaptureInputPort *port in connection.inputPorts) {
                if (port.input == input) { usesInput = YES; break; }
            }
            if (!usesInput) { continue; }
            if (connection.output != nil) {
                objc_setAssociatedObject(connection.output, CamRelayOutputConnectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (connection.videoPreviewLayer != nil) {
                objc_setAssociatedObject(connection.videoPreviewLayer, CamRelayPreviewConnectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [connections removeObject:connection];
        }
        [CamRelayMutableArray(session, CamRelaySyntheticInputsKey) removeObject:input];
        return;
    }
    OriginalRemoveInput(session, selector, input);
}

static BOOL (*OriginalCanAddOutput)(AVCaptureSession *, SEL, AVCaptureOutput *);
static BOOL CamRelayCanAddOutput(AVCaptureSession *session, SEL selector, AVCaptureOutput *output) {
    if (CamRelaySupportsOutput(output)) {
        return YES;
    }
    return OriginalCanAddOutput(session, selector, output);
}

static void CamRelayStoreSyntheticOutput(
    AVCaptureSession *session,
    AVCaptureOutput *output,
    BOOL connect
) {
    NSMutableArray *outputs = CamRelayMutableArray(session, CamRelaySyntheticOutputsKey);
    if (![outputs containsObject:output]) {
        [outputs addObject:output];
    }
    objc_setAssociatedObject(output, CamRelayOutputSessionKey, session, OBJC_ASSOCIATION_ASSIGN);
    if (connect) {
        CamRelayEnsureOutputConnection(session, output);
    }
}

static void (*OriginalAddOutput)(AVCaptureSession *, SEL, AVCaptureOutput *);
static void CamRelayAddOutput(AVCaptureSession *session, SEL selector, AVCaptureOutput *output) {
    if (CamRelaySupportsOutput(output)) {
        CamRelayStoreSyntheticOutput(session, output, YES);
        return;
    }
    OriginalAddOutput(session, selector, output);
}

static void (*OriginalAddOutputWithNoConnections)(AVCaptureSession *, SEL, AVCaptureOutput *);
static void CamRelayAddOutputWithNoConnections(
    AVCaptureSession *session,
    SEL selector,
    AVCaptureOutput *output
) {
    if (CamRelaySupportsOutput(output)) {
        CamRelayStoreSyntheticOutput(session, output, NO);
        return;
    }
    OriginalAddOutputWithNoConnections(session, selector, output);
}

static void (*OriginalRemoveOutput)(AVCaptureSession *, SEL, AVCaptureOutput *);
static void CamRelayRemoveOutput(AVCaptureSession *session, SEL selector, AVCaptureOutput *output) {
    if ([CamRelayMutableArray(session, CamRelaySyntheticOutputsKey) containsObject:output]) {
        [CamRelayMutableArray(session, CamRelaySyntheticOutputsKey) removeObject:output];
        AVCaptureConnection *connection = objc_getAssociatedObject(output, CamRelayOutputConnectionKey);
        if (connection != nil) {
            [CamRelayMutableArray(session, CamRelaySyntheticConnectionsKey) removeObject:connection];
        }
        objc_setAssociatedObject(output, CamRelayOutputConnectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(output, CamRelayOutputSessionKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return;
    }
    OriginalRemoveOutput(session, selector, output);
}

static BOOL (*OriginalCanAddConnection)(AVCaptureSession *, SEL, AVCaptureConnection *);
static BOOL CamRelayCanAddConnection(
    AVCaptureSession *session,
    SEL selector,
    AVCaptureConnection *connection
) {
    if ([connection isKindOfClass:CamRelaySyntheticConnection.class]) {
        return YES;
    }
    return OriginalCanAddConnection(session, selector, connection);
}

static void (*OriginalAddConnection)(AVCaptureSession *, SEL, AVCaptureConnection *);
static void CamRelayAddConnection(
    AVCaptureSession *session,
    SEL selector,
    AVCaptureConnection *connection
) {
    if ([connection isKindOfClass:CamRelaySyntheticConnection.class]) {
        CamRelayAddConnectionToSession(session, connection);
        return;
    }
    OriginalAddConnection(session, selector, connection);
}

static void (*OriginalRemoveConnection)(AVCaptureSession *, SEL, AVCaptureConnection *);
static void CamRelayRemoveConnection(
    AVCaptureSession *session,
    SEL selector,
    AVCaptureConnection *connection
) {
    if ([connection isKindOfClass:CamRelaySyntheticConnection.class]) {
        [CamRelayMutableArray(session, CamRelaySyntheticConnectionsKey) removeObject:connection];
        return;
    }
    OriginalRemoveConnection(session, selector, connection);
}

static NSArray<AVCaptureConnection *> *(*OriginalOutputConnections)(AVCaptureOutput *, SEL);
static NSArray<AVCaptureConnection *> *CamRelayOutputConnections(
    AVCaptureOutput *output,
    SEL selector
) {
    AVCaptureConnection *connection = objc_getAssociatedObject(output, CamRelayOutputConnectionKey);
    return connection != nil ? @[connection] : OriginalOutputConnections(output, selector);
}

static AVCaptureConnection *(*OriginalOutputConnectionWithMediaType)(
    AVCaptureOutput *, SEL, AVMediaType
);
static AVCaptureConnection *CamRelayOutputConnectionWithMediaType(
    AVCaptureOutput *output,
    SEL selector,
    AVMediaType mediaType
) {
    AVCaptureConnection *connection = objc_getAssociatedObject(output, CamRelayOutputConnectionKey);
    if (connection != nil) {
        return [mediaType isEqualToString:AVMediaTypeVideo] ? connection : nil;
    }
    return OriginalOutputConnectionWithMediaType(output, selector, mediaType);
}

static id (*OriginalConnectionInitWithOutput)(
    id, SEL, NSArray<AVCaptureInputPort *> *, AVCaptureOutput *
);
static id CamRelayConnectionInitWithOutput(
    id self,
    SEL selector,
    NSArray<AVCaptureInputPort *> *ports,
    AVCaptureOutput *output
) {
    if ([ports.firstObject isKindOfClass:CamRelaySyntheticInputPort.class]) {
        object_setClass(self, CamRelaySyntheticConnection.class);
        objc_setAssociatedObject(
            self,
            CamRelayConnectionInputPortsKey,
            ports,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        objc_setAssociatedObject(
            self,
            CamRelayConnectionOutputKey,
            output,
            OBJC_ASSOCIATION_ASSIGN
        );
        return self;
    }
    return OriginalConnectionInitWithOutput(self, selector, ports, output);
}

static id (*OriginalConnectionInitWithPreview)(
    id, SEL, AVCaptureInputPort *, AVCaptureVideoPreviewLayer *
);
static id CamRelayConnectionInitWithPreview(
    id self,
    SEL selector,
    AVCaptureInputPort *port,
    AVCaptureVideoPreviewLayer *layer
) {
    if ([port isKindOfClass:CamRelaySyntheticInputPort.class]) {
        object_setClass(self, CamRelaySyntheticConnection.class);
        objc_setAssociatedObject(
            self,
            CamRelayConnectionInputPortsKey,
            @[port],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        objc_setAssociatedObject(
            self,
            CamRelayConnectionPreviewLayerKey,
            layer,
            OBJC_ASSOCIATION_ASSIGN
        );
        return self;
    }
    return OriginalConnectionInitWithPreview(self, selector, port, layer);
}

static id (*OriginalPreviewInitWithSession)(id, SEL, AVCaptureSession *);
static id (*OriginalPreviewInitWithNoConnection)(id, SEL, AVCaptureSession *);
static id CamRelayPreviewInitWithSession(
    id self,
    SEL selector,
    AVCaptureSession *session
) {
    id layer;
    if (CamRelayIsActive() && session != nil) {
        layer = OriginalPreviewInitWithSession(self, selector, nil);
        objc_setAssociatedObject(
            layer,
            CamRelayPreviewSessionKey,
            session,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        CamRelayRegisterPreviewLayer(layer, session, YES);
    } else {
        layer = OriginalPreviewInitWithSession(self, selector, session);
    }
    return layer;
}

static id CamRelayPreviewInitWithNoConnection(
    id self,
    SEL selector,
    AVCaptureSession *session
) {
    if (CamRelayIsActive() && session != nil) {
        id layer = OriginalPreviewInitWithNoConnection(self, selector, nil);
        objc_setAssociatedObject(
            layer,
            CamRelayPreviewSessionKey,
            session,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        CamRelayRegisterPreviewLayer(layer, session, NO);
        return layer;
    }
    id layer = OriginalPreviewInitWithNoConnection(self, selector, session);
    return layer;
}

static void (*OriginalPreviewSetSession)(AVCaptureVideoPreviewLayer *, SEL, AVCaptureSession *);
static void (*OriginalPreviewSetSessionWithNoConnection)(
    AVCaptureVideoPreviewLayer *, SEL, AVCaptureSession *
);
static void CamRelayPreviewSetSession(
    AVCaptureVideoPreviewLayer *layer,
    SEL selector,
    AVCaptureSession *session
) {
    AVCaptureSession *syntheticSession = objc_getAssociatedObject(layer, CamRelayPreviewSessionKey);
    if (CamRelayIsActive() || syntheticSession != nil) {
        if (syntheticSession != nil && syntheticSession != session) {
            NSHashTable *layers = objc_getAssociatedObject(syntheticSession, CamRelayPreviewLayersKey);
            [layers removeObject:layer];
        }
        objc_setAssociatedObject(
            layer,
            CamRelayPreviewSessionKey,
            session,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        if (session != nil) {
            CamRelayRegisterPreviewLayer(layer, session, YES);
        }
        return;
    }
    OriginalPreviewSetSession(layer, selector, session);
}

static void CamRelayPreviewSetSessionWithNoConnection(
    AVCaptureVideoPreviewLayer *layer,
    SEL selector,
    AVCaptureSession *session
) {
    if (CamRelayIsActive() || objc_getAssociatedObject(layer, CamRelayPreviewSessionKey) != nil) {
        CamRelayPreviewSetSession(layer, @selector(setSession:), session);
        return;
    }
    OriginalPreviewSetSessionWithNoConnection(layer, selector, session);
}

static AVCaptureSession *(*OriginalPreviewSession)(AVCaptureVideoPreviewLayer *, SEL);
static AVCaptureSession *CamRelayPreviewSession(
    AVCaptureVideoPreviewLayer *layer,
    SEL selector
) {
    return objc_getAssociatedObject(layer, CamRelayPreviewSessionKey)
        ?: OriginalPreviewSession(layer, selector);
}

static AVCaptureConnection *(*OriginalPreviewConnection)(AVCaptureVideoPreviewLayer *, SEL);
static AVCaptureConnection *CamRelayPreviewConnection(
    AVCaptureVideoPreviewLayer *layer,
    SEL selector
) {
    return objc_getAssociatedObject(layer, CamRelayPreviewConnectionKey)
        ?: OriginalPreviewConnection(layer, selector);
}

static BOOL (*OriginalPreviewing)(AVCaptureVideoPreviewLayer *, SEL);
static BOOL CamRelayPreviewing(AVCaptureVideoPreviewLayer *layer, SEL selector) {
    AVCaptureConnection *connection = objc_getAssociatedObject(layer, CamRelayPreviewConnectionKey);
    if (connection != nil) {
        AVCaptureSession *session = objc_getAssociatedObject(layer, CamRelayPreviewSessionKey)
            ?: layer.session;
        return connection.isEnabled &&
            [objc_getAssociatedObject(session, CamRelayRunningKey) boolValue];
    }
    return OriginalPreviewing(layer, selector);
}

static NSArray<NSNumber *> *(*OriginalAvailableVideoPixelFormats)(AVCaptureVideoDataOutput *, SEL);
static NSArray<NSNumber *> *CamRelayAvailableVideoPixelFormats(
    AVCaptureVideoDataOutput *output,
    SEL selector
) {
    if (objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil) {
        return @[
            @(kCVPixelFormatType_32BGRA),
            @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        ];
    }
    return OriginalAvailableVideoPixelFormats(output, selector);
}

static id (*OriginalPhotoOutputInitializer)(AVCapturePhotoOutput *, SEL);
static id CamRelayPhotoOutputInitializer(AVCapturePhotoOutput *output, SEL selector) {
    id previous = CamRelayBeginCaptureOutputConstruction();
    @try {
        return OriginalPhotoOutputInitializer(output, selector);
    } @finally {
        CamRelayEndCaptureOutputConstruction(previous);
    }
}

static id (*OriginalMovieOutputInitializer)(AVCaptureMovieFileOutput *, SEL);
static id CamRelayMovieOutputInitializer(AVCaptureMovieFileOutput *output, SEL selector) {
    id previous = CamRelayBeginCaptureOutputConstruction();
    @try {
        return OriginalMovieOutputInitializer(output, selector);
    } @finally {
        CamRelayEndCaptureOutputConstruction(previous);
    }
}

static AVCapturePhotoSettings *(*OriginalPhotoSettingsFactory)(Class, SEL);
static AVCapturePhotoSettings *CamRelayPhotoSettingsFactory(Class class, SEL selector) {
    id previous = CamRelayBeginCaptureOutputConstruction();
    @try {
        return OriginalPhotoSettingsFactory(class, selector);
    } @finally {
        CamRelayEndCaptureOutputConstruction(previous);
    }
}

static AVCapturePhotoSettings *(*OriginalPhotoSettingsWithFormatFactory)(
    Class, SEL, NSDictionary *
);
static AVCapturePhotoSettings *CamRelayPhotoSettingsWithFormatFactory(
    Class class,
    SEL selector,
    NSDictionary *format
) {
    id previous = CamRelayBeginCaptureOutputConstruction();
    @try {
        return OriginalPhotoSettingsWithFormatFactory(class, selector, format);
    } @finally {
        CamRelayEndCaptureOutputConstruction(previous);
    }
}

static void (*OriginalCapturePhoto)(
    AVCapturePhotoOutput *, SEL, AVCapturePhotoSettings *, id<AVCapturePhotoCaptureDelegate>
);
static void CamRelayCapturePhoto(
    AVCapturePhotoOutput *output,
    SEL selector,
    AVCapturePhotoSettings *settings,
    id<AVCapturePhotoCaptureDelegate> delegate
) {
    AVCaptureSession *session = objc_getAssociatedObject(output, CamRelayOutputSessionKey);
    if (session == nil) {
        OriginalCapturePhoto(output, selector, settings, delegate);
        return;
    }
    CamRelayPhotoRequest *request = [[CamRelayPhotoRequest alloc] init];
    request.output = output;
    request.settings = settings;
    request.delegate = delegate;
    NSMutableArray *requests = CamRelayMutableArray(session, CamRelayPhotoRequestsKey);
    @synchronized(requests) {
        [requests addObject:request];
    }
}

static NSArray<NSNumber *> *(*OriginalPhotoPixelFormats)(AVCapturePhotoOutput *, SEL);
static NSArray<NSNumber *> *CamRelayPhotoPixelFormats(AVCapturePhotoOutput *output, SEL selector) {
    return objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil
        ? @[@(kCVPixelFormatType_32BGRA)]
        : OriginalPhotoPixelFormats(output, selector);
}

static NSArray<AVVideoCodecType> *(*OriginalPhotoCodecs)(AVCapturePhotoOutput *, SEL);
static NSArray<AVVideoCodecType> *CamRelayPhotoCodecs(AVCapturePhotoOutput *output, SEL selector) {
    return objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil
        ? @[AVVideoCodecTypeJPEG]
        : OriginalPhotoCodecs(output, selector);
}

static NSArray<AVFileType> *(*OriginalPhotoFileTypes)(AVCapturePhotoOutput *, SEL);
static NSArray<AVFileType> *CamRelayPhotoFileTypes(AVCapturePhotoOutput *output, SEL selector) {
    return objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil
        ? @[AVFileTypeJPEG]
        : OriginalPhotoFileTypes(output, selector);
}

static NSArray<NSNumber *> *(*OriginalSupportedFlashModes)(AVCapturePhotoOutput *, SEL);
static NSArray<NSNumber *> *CamRelaySupportedFlashModes(AVCapturePhotoOutput *output, SEL selector) {
    return objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil
        ? @[@(AVCaptureFlashModeOff)]
        : OriginalSupportedFlashModes(output, selector);
}

static NSArray<AVVideoCodecType> *(*OriginalMovieCodecs)(AVCaptureMovieFileOutput *, SEL);
static NSArray<AVVideoCodecType> *CamRelayMovieCodecs(
    AVCaptureMovieFileOutput *output,
    SEL selector
) {
    return objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil
        ? @[AVVideoCodecTypeH264]
        : OriginalMovieCodecs(output, selector);
}

static NSDictionary *(*OriginalMovieOutputSettings)(
    AVCaptureMovieFileOutput *, SEL, AVCaptureConnection *
);
static NSDictionary *CamRelayMovieOutputSettings(
    AVCaptureMovieFileOutput *output,
    SEL selector,
    AVCaptureConnection *connection
) {
    if ([connection isKindOfClass:CamRelaySyntheticConnection.class]) {
        return objc_getAssociatedObject(output, CamRelayMovieOutputSettingsKey) ?: @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(CamRelayFixtureWidth()),
            AVVideoHeightKey: @(CamRelayFixtureHeight()),
        };
    }
    return OriginalMovieOutputSettings(output, selector, connection);
}

static void (*OriginalSetMovieOutputSettings)(
    AVCaptureMovieFileOutput *, SEL, NSDictionary *, AVCaptureConnection *
);
static void CamRelaySetMovieOutputSettings(
    AVCaptureMovieFileOutput *output,
    SEL selector,
    NSDictionary *settings,
    AVCaptureConnection *connection
) {
    if ([connection isKindOfClass:CamRelaySyntheticConnection.class]) {
        objc_setAssociatedObject(
            output,
            CamRelayMovieOutputSettingsKey,
            settings,
            OBJC_ASSOCIATION_COPY_NONATOMIC
        );
        return;
    }
    OriginalSetMovieOutputSettings(output, selector, settings, connection);
}

static void (*OriginalStartRecording)(
    AVCaptureFileOutput *, SEL, NSURL *, id<AVCaptureFileOutputRecordingDelegate>
);
static void CamRelayStartRecording(
    AVCaptureFileOutput *output,
    SEL selector,
    NSURL *url,
    id<AVCaptureFileOutputRecordingDelegate> delegate
) {
    if ([output isKindOfClass:AVCaptureMovieFileOutput.class] &&
        objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil) {
        CamRelayMovieRecorder *recorder = objc_getAssociatedObject(output, CamRelayMovieRecorderKey);
        if (recorder == nil) {
            recorder = [[CamRelayMovieRecorder alloc] init];
            recorder.output = (AVCaptureMovieFileOutput *)output;
            objc_setAssociatedObject(
                output,
                CamRelayMovieRecorderKey,
                recorder,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
        [recorder startAtURL:url delegate:delegate];
        return;
    }
    OriginalStartRecording(output, selector, url, delegate);
}

static void (*OriginalStopRecording)(AVCaptureFileOutput *, SEL);
static void CamRelayStopRecording(AVCaptureFileOutput *output, SEL selector) {
    CamRelayMovieRecorder *recorder = objc_getAssociatedObject(output, CamRelayMovieRecorderKey);
    if (recorder != nil) {
        [recorder stop];
        return;
    }
    OriginalStopRecording(output, selector);
}

static BOOL (*OriginalIsRecording)(AVCaptureFileOutput *, SEL);
static BOOL CamRelayIsRecording(AVCaptureFileOutput *output, SEL selector) {
    CamRelayMovieRecorder *recorder = objc_getAssociatedObject(output, CamRelayMovieRecorderKey);
    return recorder != nil ? recorder.recording : OriginalIsRecording(output, selector);
}

static NSURL *(*OriginalOutputFileURL)(AVCaptureFileOutput *, SEL);
static NSURL *CamRelayOutputFileURL(AVCaptureFileOutput *output, SEL selector) {
    CamRelayMovieRecorder *recorder = objc_getAssociatedObject(output, CamRelayMovieRecorderKey);
    return recorder != nil ? recorder.url : OriginalOutputFileURL(output, selector);
}

static NSArray<AVMetadataObjectType> *(*OriginalAvailableMetadataTypes)(
    AVCaptureMetadataOutput *, SEL
);
static NSArray<AVMetadataObjectType> *CamRelayAvailableMetadataTypes(
    AVCaptureMetadataOutput *output,
    SEL selector
) {
    return objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil
        ? @[AVMetadataObjectTypeQRCode]
        : OriginalAvailableMetadataTypes(output, selector);
}

static NSArray<AVMetadataObjectType> *(*OriginalMetadataTypes)(AVCaptureMetadataOutput *, SEL);
static NSArray<AVMetadataObjectType> *CamRelayMetadataTypes(
    AVCaptureMetadataOutput *output,
    SEL selector
) {
    NSArray *types = objc_getAssociatedObject(output, CamRelayMetadataTypesKey);
    return types != nil ? types : OriginalMetadataTypes(output, selector);
}

static void (*OriginalSetMetadataTypes)(
    AVCaptureMetadataOutput *, SEL, NSArray<AVMetadataObjectType> *
);
static void CamRelaySetMetadataTypes(
    AVCaptureMetadataOutput *output,
    SEL selector,
    NSArray<AVMetadataObjectType> *types
) {
    if (objc_getAssociatedObject(output, CamRelayOutputSessionKey) != nil) {
        NSSet *available = [NSSet setWithObject:AVMetadataObjectTypeQRCode];
        for (AVMetadataObjectType type in types) {
            if (![available containsObject:type]) {
                [NSException raise:NSInvalidArgumentException
                    format:@"Unsupported synthetic metadata type: %@", type];
            }
        }
        objc_setAssociatedObject(
            output,
            CamRelayMetadataTypesKey,
            types,
            OBJC_ASSOCIATION_COPY_NONATOMIC
        );
        return;
    }
    OriginalSetMetadataTypes(output, selector, types);
}

static void (*OriginalStartRunning)(AVCaptureSession *, SEL);
static void CamRelayStartRunning(AVCaptureSession *session, SEL selector) {
    if (CamRelaySessionUsesSyntheticCamera(session)) {
        if ([objc_getAssociatedObject(session, CamRelayRunningKey) boolValue]) {
            return;
        }
        NSArray<AVCaptureVideoPreviewLayer *> *previewLayers =
            [objc_getAssociatedObject(session, CamRelayPreviewLayersKey) allObjects];
        for (AVCaptureVideoPreviewLayer *layer in previewLayers) {
            [layer willChangeValueForKey:@"previewing"];
        }
        CamRelayFrameEmitter *emitter = [[CamRelayFrameEmitter alloc] init];
        objc_setAssociatedObject(session, CamRelayEmitterKey, emitter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(session, CamRelayRunningKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (AVCaptureVideoPreviewLayer *layer in previewLayers) {
            [layer didChangeValueForKey:@"previewing"];
        }
        [emitter startWithSession:session];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:AVCaptureSessionDidStartRunningNotification
                          object:session];
        NSLog(@"[CamRelayRuntime] synthetic capture started");
        return;
    }
    OriginalStartRunning(session, selector);
}

static void (*OriginalStopRunning)(AVCaptureSession *, SEL);
static void CamRelayStopRunning(AVCaptureSession *session, SEL selector) {
    CamRelayFrameEmitter *emitter = objc_getAssociatedObject(session, CamRelayEmitterKey);
    if (emitter != nil) {
        NSArray<AVCaptureVideoPreviewLayer *> *previewLayers =
            [objc_getAssociatedObject(session, CamRelayPreviewLayersKey) allObjects];
        for (AVCaptureVideoPreviewLayer *layer in previewLayers) {
            [layer willChangeValueForKey:@"previewing"];
        }
        [emitter stop];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (AVCaptureVideoPreviewLayer *layer in previewLayers) {
                AVSampleBufferDisplayLayer *displayLayer = objc_getAssociatedObject(
                    layer,
                    CamRelayPreviewDisplayLayerKey
                );
                [displayLayer.sampleBufferRenderer
                    flushWithRemovalOfDisplayedImage:YES
                    completionHandler:nil];
            }
        });
        objc_setAssociatedObject(session, CamRelayEmitterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(session, CamRelayRunningKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (AVCaptureVideoPreviewLayer *layer in previewLayers) {
            [layer didChangeValueForKey:@"previewing"];
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:AVCaptureSessionDidStopRunningNotification
                          object:session];
        return;
    }
    OriginalStopRunning(session, selector);
}

static BOOL (*OriginalIsRunning)(AVCaptureSession *, SEL);
static BOOL CamRelayIsRunning(AVCaptureSession *session, SEL selector) {
    NSNumber *running = objc_getAssociatedObject(session, CamRelayRunningKey);
    return running != nil ? running.boolValue : OriginalIsRunning(session, selector);
}

static void (*OriginalPostRuntimeError)(AVCaptureSession *, SEL, NSError *);
static void CamRelayPostRuntimeError(
    AVCaptureSession *session,
    SEL selector,
    NSError *error
) {
    NSError *underlyingError = error.userInfo[NSUnderlyingErrorKey];
    BOOL isExpectedSyntheticGraphError =
        CamRelaySessionUsesSyntheticCamera(session) &&
        [error.domain isEqualToString:AVFoundationErrorDomain] &&
        error.code == AVErrorUnknown &&
        [underlyingError.domain isEqualToString:NSOSStatusErrorDomain] &&
        underlyingError.code == -12782;
    if (isExpectedSyntheticGraphError) {
        NSLog(@"[CamRelayRuntime] ignored native graph error for synthetic capture");
        return;
    }
    OriginalPostRuntimeError(session, selector, error);
}

static void CamRelayReplaceInstanceMethod(Class class, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(class, selector);
    if (method == NULL) {
        return;
    }
    *original = method_setImplementation(method, replacement);
}

static void CamRelayReplaceClassMethod(Class class, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getClassMethod(class, selector);
    if (method == NULL) {
        return;
    }
    *original = method_setImplementation(method, replacement);
}

__attribute__((constructor))
static void CamRelayRuntimeDidLoad(void) {
    const char *port = getenv("CAMRELAY_PORT");
    if (port == NULL || !CamRelayStartControlConnection()) {
        return;
    }

    // Synthetic connections own associated objects, not a native capture graph.
    // NSObject teardown releases that state without invoking AVFoundation's
    // destructor, which requires its private connection storage to be initialized.
    SEL deallocSelector = sel_registerName("dealloc");
    Method objectDeallocator = class_getInstanceMethod(NSObject.class, deallocSelector);
    class_addMethod(CamRelaySyntheticConnection.class, deallocSelector,
        method_getImplementation(objectDeallocator), method_getTypeEncoding(objectDeallocator));

    CamRelayReplaceClassMethod(
        AVCaptureDeviceDiscoverySession.class,
        @selector(discoverySessionWithDeviceTypes:mediaType:position:),
        (IMP)CamRelayDiscoverySessionFactory,
        (IMP *)&OriginalDiscoverySessionFactory
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureDeviceDiscoverySession.class,
        @selector(devices),
        (IMP)CamRelayDiscoveryDevices,
        (IMP *)&OriginalDiscoveryDevices
    );
    CamRelayReplaceClassMethod(
        AVCaptureDevice.class,
        @selector(devicesWithMediaType:),
        (IMP)CamRelayDevicesWithMediaType,
        (IMP *)&OriginalDevicesWithMediaType
    );
    CamRelayReplaceClassMethod(
        AVCaptureDevice.class,
        @selector(deviceWithUniqueID:),
        (IMP)CamRelayDeviceWithUniqueID,
        (IMP *)&OriginalDeviceWithUniqueID
    );
    CamRelayReplaceClassMethod(
        AVCaptureDevice.class,
        @selector(defaultDeviceWithMediaType:),
        (IMP)CamRelayDefaultDeviceWithMediaType,
        (IMP *)&OriginalDefaultDeviceWithMediaType
    );
    CamRelayReplaceClassMethod(
        AVCaptureDevice.class,
        @selector(defaultDeviceWithDeviceType:mediaType:position:),
        (IMP)CamRelayDefaultDeviceWithType,
        (IMP *)&OriginalDefaultDeviceWithType
    );
    CamRelayReplaceClassMethod(
        AVCaptureDevice.class,
        @selector(authorizationStatusForMediaType:),
        (IMP)CamRelayAuthorizationStatus,
        (IMP *)&OriginalAuthorizationStatus
    );
    CamRelayReplaceClassMethod(
        AVCaptureDevice.class,
        @selector(requestAccessForMediaType:completionHandler:),
        (IMP)CamRelayRequestAccess,
        (IMP *)&OriginalRequestAccess
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureDeviceInput.class,
        @selector(initWithDevice:error:),
        (IMP)CamRelayDeviceInputInitializer,
        (IMP *)&OriginalDeviceInputInitializer
    );

    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(inputs),
        (IMP)CamRelaySessionInputs,
        (IMP *)&OriginalSessionInputs
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(outputs),
        (IMP)CamRelaySessionOutputs,
        (IMP *)&OriginalSessionOutputs
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(connections),
        (IMP)CamRelaySessionConnections,
        (IMP *)&OriginalSessionConnections
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(commitConfiguration),
        (IMP)CamRelayCommitConfiguration,
        (IMP *)&OriginalCommitConfiguration
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(canSetSessionPreset:),
        (IMP)CamRelayCanSetSessionPreset,
        (IMP *)&OriginalCanSetSessionPreset
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(sessionPreset),
        (IMP)CamRelaySessionPreset,
        (IMP *)&OriginalSessionPreset
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(setSessionPreset:),
        (IMP)CamRelaySetSessionPreset,
        (IMP *)&OriginalSetSessionPreset
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(canAddInput:),
        (IMP)CamRelayCanAddInput,
        (IMP *)&OriginalCanAddInput
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(addInput:),
        (IMP)CamRelayAddInput,
        (IMP *)&OriginalAddInput
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(addInputWithNoConnections:),
        (IMP)CamRelayAddInputWithNoConnections,
        (IMP *)&OriginalAddInputWithNoConnections
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(removeInput:),
        (IMP)CamRelayRemoveInput,
        (IMP *)&OriginalRemoveInput
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(canAddOutput:),
        (IMP)CamRelayCanAddOutput,
        (IMP *)&OriginalCanAddOutput
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(addOutput:),
        (IMP)CamRelayAddOutput,
        (IMP *)&OriginalAddOutput
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(addOutputWithNoConnections:),
        (IMP)CamRelayAddOutputWithNoConnections,
        (IMP *)&OriginalAddOutputWithNoConnections
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(removeOutput:),
        (IMP)CamRelayRemoveOutput,
        (IMP *)&OriginalRemoveOutput
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(canAddConnection:),
        (IMP)CamRelayCanAddConnection,
        (IMP *)&OriginalCanAddConnection
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(addConnection:),
        (IMP)CamRelayAddConnection,
        (IMP *)&OriginalAddConnection
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(removeConnection:),
        (IMP)CamRelayRemoveConnection,
        (IMP *)&OriginalRemoveConnection
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(startRunning),
        (IMP)CamRelayStartRunning,
        (IMP *)&OriginalStartRunning
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(stopRunning),
        (IMP)CamRelayStopRunning,
        (IMP *)&OriginalStopRunning
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        @selector(isRunning),
        (IMP)CamRelayIsRunning,
        (IMP *)&OriginalIsRunning
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureSession.class,
        NSSelectorFromString(@"_postRuntimeError:"),
        (IMP)CamRelayPostRuntimeError,
        (IMP *)&OriginalPostRuntimeError
    );

    CamRelayReplaceInstanceMethod(
        AVCaptureOutput.class,
        @selector(connections),
        (IMP)CamRelayOutputConnections,
        (IMP *)&OriginalOutputConnections
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureOutput.class,
        @selector(connectionWithMediaType:),
        (IMP)CamRelayOutputConnectionWithMediaType,
        (IMP *)&OriginalOutputConnectionWithMediaType
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureConnection.class,
        @selector(initWithInputPorts:output:),
        (IMP)CamRelayConnectionInitWithOutput,
        (IMP *)&OriginalConnectionInitWithOutput
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureConnection.class,
        @selector(initWithInputPort:videoPreviewLayer:),
        (IMP)CamRelayConnectionInitWithPreview,
        (IMP *)&OriginalConnectionInitWithPreview
    );

    CamRelayReplaceInstanceMethod(
        AVCaptureVideoPreviewLayer.class,
        @selector(initWithSession:),
        (IMP)CamRelayPreviewInitWithSession,
        (IMP *)&OriginalPreviewInitWithSession
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureVideoPreviewLayer.class,
        @selector(initWithSessionWithNoConnection:),
        (IMP)CamRelayPreviewInitWithNoConnection,
        (IMP *)&OriginalPreviewInitWithNoConnection
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureVideoPreviewLayer.class,
        @selector(setSession:),
        (IMP)CamRelayPreviewSetSession,
        (IMP *)&OriginalPreviewSetSession
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureVideoPreviewLayer.class,
        @selector(setSessionWithNoConnection:),
        (IMP)CamRelayPreviewSetSessionWithNoConnection,
        (IMP *)&OriginalPreviewSetSessionWithNoConnection
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureVideoPreviewLayer.class,
        @selector(session),
        (IMP)CamRelayPreviewSession,
        (IMP *)&OriginalPreviewSession
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureVideoPreviewLayer.class,
        @selector(connection),
        (IMP)CamRelayPreviewConnection,
        (IMP *)&OriginalPreviewConnection
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureVideoPreviewLayer.class,
        @selector(isPreviewing),
        (IMP)CamRelayPreviewing,
        (IMP *)&OriginalPreviewing
    );

    CamRelayReplaceInstanceMethod(
        AVCaptureVideoDataOutput.class,
        @selector(availableVideoPixelFormatTypes),
        (IMP)CamRelayAvailableVideoPixelFormats,
        (IMP *)&OriginalAvailableVideoPixelFormats
    );
    CamRelayReplaceInstanceMethod(
        AVCapturePhotoOutput.class,
        @selector(init),
        (IMP)CamRelayPhotoOutputInitializer,
        (IMP *)&OriginalPhotoOutputInitializer
    );
    CamRelayReplaceClassMethod(
        AVCapturePhotoSettings.class,
        @selector(photoSettings),
        (IMP)CamRelayPhotoSettingsFactory,
        (IMP *)&OriginalPhotoSettingsFactory
    );
    CamRelayReplaceClassMethod(
        AVCapturePhotoSettings.class,
        @selector(photoSettingsWithFormat:),
        (IMP)CamRelayPhotoSettingsWithFormatFactory,
        (IMP *)&OriginalPhotoSettingsWithFormatFactory
    );
    CamRelayReplaceInstanceMethod(
        AVCapturePhotoOutput.class,
        @selector(capturePhotoWithSettings:delegate:),
        (IMP)CamRelayCapturePhoto,
        (IMP *)&OriginalCapturePhoto
    );
    CamRelayReplaceInstanceMethod(
        AVCapturePhotoOutput.class,
        @selector(availablePhotoPixelFormatTypes),
        (IMP)CamRelayPhotoPixelFormats,
        (IMP *)&OriginalPhotoPixelFormats
    );
    CamRelayReplaceInstanceMethod(
        AVCapturePhotoOutput.class,
        @selector(availablePhotoCodecTypes),
        (IMP)CamRelayPhotoCodecs,
        (IMP *)&OriginalPhotoCodecs
    );
    CamRelayReplaceInstanceMethod(
        AVCapturePhotoOutput.class,
        @selector(availablePhotoFileTypes),
        (IMP)CamRelayPhotoFileTypes,
        (IMP *)&OriginalPhotoFileTypes
    );
    CamRelayReplaceInstanceMethod(
        AVCapturePhotoOutput.class,
        @selector(supportedFlashModes),
        (IMP)CamRelaySupportedFlashModes,
        (IMP *)&OriginalSupportedFlashModes
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMovieFileOutput.class,
        @selector(init),
        (IMP)CamRelayMovieOutputInitializer,
        (IMP *)&OriginalMovieOutputInitializer
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMovieFileOutput.class,
        @selector(availableVideoCodecTypes),
        (IMP)CamRelayMovieCodecs,
        (IMP *)&OriginalMovieCodecs
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMovieFileOutput.class,
        @selector(outputSettingsForConnection:),
        (IMP)CamRelayMovieOutputSettings,
        (IMP *)&OriginalMovieOutputSettings
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMovieFileOutput.class,
        @selector(setOutputSettings:forConnection:),
        (IMP)CamRelaySetMovieOutputSettings,
        (IMP *)&OriginalSetMovieOutputSettings
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMovieFileOutput.class,
        @selector(startRecordingToOutputFileURL:recordingDelegate:),
        (IMP)CamRelayStartRecording,
        (IMP *)&OriginalStartRecording
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMovieFileOutput.class,
        @selector(stopRecording),
        (IMP)CamRelayStopRecording,
        (IMP *)&OriginalStopRecording
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMovieFileOutput.class,
        @selector(isRecording),
        (IMP)CamRelayIsRecording,
        (IMP *)&OriginalIsRecording
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMovieFileOutput.class,
        @selector(outputFileURL),
        (IMP)CamRelayOutputFileURL,
        (IMP *)&OriginalOutputFileURL
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMetadataOutput.class,
        @selector(availableMetadataObjectTypes),
        (IMP)CamRelayAvailableMetadataTypes,
        (IMP *)&OriginalAvailableMetadataTypes
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMetadataOutput.class,
        @selector(metadataObjectTypes),
        (IMP)CamRelayMetadataTypes,
        (IMP *)&OriginalMetadataTypes
    );
    CamRelayReplaceInstanceMethod(
        AVCaptureMetadataOutput.class,
        @selector(setMetadataObjectTypes:),
        (IMP)CamRelaySetMetadataTypes,
        (IMP *)&OriginalSetMetadataTypes
    );

    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"(no bundle identifier)";
    NSLog(
        @"[CamRelayRuntime] loaded in %@ on port %s using %@",
        bundleIdentifier,
        port,
        CamRelayRuntimeArchitecture()
    );
}
