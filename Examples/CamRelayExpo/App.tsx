import { useEffect, useReducer, useRef, useState } from 'react'
import {
  AccessibilityInfo,
  ActivityIndicator,
  AppState,
  Image,
  Linking,
  Modal,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native'
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context'
import {
  Camera,
  type CameraRuntimeError,
  useCameraDevice,
  useCameraDevices,
  useCameraPermission,
} from 'react-native-vision-camera'
import { captureReducer, initialCaptureState, type CapturedPhoto } from './captureFlow'

export default function App() {
  return (
    <SafeAreaProvider>
      <CameraExample />
    </SafeAreaProvider>
  )
}

function CameraExample() {
  const camera = useRef<Camera>(null)
  const captureInFlight = useRef(false)
  const [captureState, dispatch] = useReducer(captureReducer, initialCaptureState)
  const [position, setPosition] = useState<'front' | 'back'>('front')
  const [initialized, setInitialized] = useState(false)
  const [previewStarted, setPreviewStarted] = useState(false)
  const [switching, setSwitching] = useState(false)
  const [cameraKey, setCameraKey] = useState(0)
  const [cameraError, setCameraError] = useState<CameraRuntimeError>()
  const [isAppActive, setAppActive] = useState(AppState.currentState === 'active')
  const [permissionBusy, setPermissionBusy] = useState(false)
  const [permissionError, setPermissionError] = useState<string>()
  const device = useCameraDevice(position)
  const devices = useCameraDevices()
  const { hasPermission, requestPermission } = useCameraPermission()
  const otherPosition = position === 'front' ? 'back' : 'front'
  const canSwitch = devices.some((candidate) => candidate.position === otherPosition)
  const ready = initialized && previewStarted && isAppActive && cameraError == null
  const captureDisabled = !ready || captureState.capturing

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => setAppActive(state === 'active'))
    return () => subscription.remove()
  }, [])

  const openCameraAccess = async () => {
    setPermissionBusy(true)
    setPermissionError(undefined)
    try {
      const status = Camera.getCameraPermissionStatus()
      if (status === 'denied' || status === 'restricted') await Linking.openSettings()
      else await requestPermission()
    } catch (error) {
      setPermissionError(error instanceof Error ? error.message : String(error))
    } finally {
      setPermissionBusy(false)
    }
  }

  const switchCamera = () => {
    if (!canSwitch || captureInFlight.current || switching || captureState.reviewVisible) return
    setSwitching(true)
    setInitialized(false)
    setCameraError(undefined)
    dispatch({ type: 'dismiss-error' })
    setPosition(otherPosition)
  }

  const retryCamera = () => {
    if (captureInFlight.current) return
    setInitialized(false)
    setPreviewStarted(false)
    setSwitching(false)
    setCameraError(undefined)
    dispatch({ type: 'dismiss-error' })
    setCameraKey((key) => key + 1)
  }

  const capture = async () => {
    // The ref also blocks two presses before React renders the disabled button.
    if (!ready || captureInFlight.current || captureState.reviewVisible) return
    captureInFlight.current = true
    dispatch({ type: 'start' })
    try {
      const result = await camera.current?.takePhoto({ enableShutterSound: false })
      if (result == null) throw new Error('Camera is not ready')
      dispatch({ type: 'success', path: result.path, width: result.width, height: result.height, position })
      AccessibilityInfo.announceForAccessibility('Photo captured. Photo review is open.')
      console.info(`[CameraExample] ${position} captured ${result.width}x${result.height} path=${result.path}`)
    } catch (error) {
      dispatch({ type: 'failure', message: error instanceof Error ? error.message : String(error) })
    } finally {
      captureInFlight.current = false
    }
  }

  const closeReview = () => dispatch({ type: 'close-review' })

  // The example exposes its ordinary capture actions to command-driven UI tests.
  // These URLs do not select fixtures or communicate with the camera relay.
  const testActions = useRef<((action: string) => void) | undefined>(undefined)
  testActions.current = (action) => {
    if (action === 'capture') void capture()
    if (action === 'switch-camera') switchCamera()
    if (action === 'review-photo') dispatch({ type: 'open-review' })
    if (action === 'close-photo') closeReview()
    if (action === 'retry-camera' && !captureState.reviewVisible) retryCamera()
  }
  useEffect(() => {
    const subscription = Linking.addEventListener('url', ({ url }) => {
      const match = /^org\.camrelay\.expo:\/\/(capture|switch-camera|review-photo|close-photo|retry-camera)\/?$/.exec(url)
      if (match != null) testActions.current?.(match[1])
    })
    return () => subscription.remove()
  }, [])

  if (!hasPermission) {
    const permission = Camera.getCameraPermissionStatus()
    const needsSettings = permission === 'denied' || permission === 'restricted'
    return (
      <CenteredMessage
        title={needsSettings ? 'Camera access is off' : 'Enable your camera'}
        detail={needsSettings
          ? 'Allow camera access in Settings, then return here to take photos.'
          : 'Allow camera access to see the live preview and take photos. Photos stay in this app’s temporary files.'}
      >
        {permissionError != null && <Text style={styles.error} accessibilityRole="alert">{permissionError}</Text>}
        <ActionButton label={needsSettings ? 'Open Settings' : 'Allow camera access'} busy={permissionBusy}
          disabled={permissionBusy} onPress={() => void openCameraAccess()} />
      </CenteredMessage>
    )
  }

  if (device == null) {
    return (
      <CenteredMessage
        title="No camera available"
        detail="In Simulator, start CamRelay and relaunch this app to connect the camera. On a device, check that a camera is available."
      >
        {canSwitch && <ActionButton label={`Use ${otherPosition} camera`} onPress={switchCamera} />}
      </CenteredMessage>
    )
  }

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView contentContainerStyle={styles.liveContent} alwaysBounceVertical={false}>
        <View style={styles.header}>
          <View style={styles.heading}>
            <Text style={styles.eyebrow}>CAMRELAY EXPO</Text>
            <Text style={styles.title} accessibilityRole="header">Camera</Text>
            <Text style={styles.device}>{device.name}</Text>
          </View>
          <Text style={styles.count} accessibilityLabel={`${captureState.count} photos captured`}>
            {captureState.count} {captureState.count === 1 ? 'photo' : 'photos'}
          </Text>
        </View>

        <View testID="camera-preview" style={styles.viewfinder}>
          <Camera
            key={cameraKey}
            ref={camera}
            style={StyleSheet.absoluteFill}
            device={device}
            isActive={isAppActive}
            photo
            resizeMode="contain"
            onError={(error) => { setCameraError(error); setSwitching(false) }}
            onInitialized={() => { setInitialized(true); setSwitching(false) }}
            onPreviewStarted={() => setPreviewStarted(true)}
            onPreviewStopped={() => setPreviewStarted(false)}
          />
          {ready && !captureState.capturing && (
            <View style={styles.previewBadge} pointerEvents="none">
              <View style={styles.liveDot} />
              <Text style={styles.badgeText}>Live preview</Text>
            </View>
          )}
          {(!ready || captureState.capturing) && (
            <View style={styles.previewOverlay}>
              {cameraError == null && <ActivityIndicator color="#8df7c1" size="large" />}
              <Text style={styles.overlayTitle} accessibilityRole={cameraError == null ? 'text' : 'alert'}>
                {cameraError != null ? 'Camera interrupted'
                  : captureState.capturing ? 'Capturing photo…'
                  : !isAppActive ? 'Camera paused'
                  : switching ? 'Switching camera…' : 'Starting camera…'}
              </Text>
              {cameraError != null && <>
                <Text style={styles.overlayDetail}>{cameraError.message}</Text>
                <ActionButton label="Retry camera" disabled={captureState.capturing} onPress={retryCamera} />
              </>}
            </View>
          )}
        </View>

        <View style={styles.footer}>
          <Text style={styles.cameraStatus}>
            Camera: {cameraError != null ? 'error' : initialized ? 'active' : 'starting'}
            {'  ·  '}Preview: {previewStarted ? 'active' : 'starting'}
          </Text>
          {captureState.error != null && (
            <View style={styles.errorCard} accessibilityRole="alert">
              <Text style={styles.errorTitle}>Photo not captured</Text>
              <Text style={styles.error}>{captureState.error}</Text>
              <Text style={styles.error}>
                {captureState.photo != null ? 'Your last photo is unchanged. ' : ''}Try taking the photo again.
              </Text>
            </View>
          )}
          {captureState.photo != null ? (
            <Pressable style={({ pressed }) => [styles.lastPhoto, captureState.capturing && styles.disabled, pressed && styles.pressed]}
              accessibilityRole="button" accessibilityLabel={`View photo ${captureState.photo.number}`}
              accessibilityState={{ disabled: captureState.capturing }} disabled={captureState.capturing}
              onPress={() => dispatch({ type: 'open-review' })}>
              <Image source={{ uri: captureState.photo.uri }} style={styles.thumbnail} resizeMode="contain" />
              <View style={styles.heading}>
                <Text style={styles.lastPhotoTitle}>Last photo</Text>
                <Text style={styles.device}>
                  {captureState.photo.position === 'front' ? 'Front' : 'Back'} camera · {captureState.photo.width} × {captureState.photo.height}
                </Text>
              </View>
              <Text style={styles.linkText}>View ›</Text>
            </Pressable>
          ) : <Text style={styles.hint}>Take a photo to open its preview. You can keep capturing without leaving the app.</Text>}
          <ActionButton label={captureState.capturing ? 'Capturing…' : captureState.error != null ? 'Try photo again' : 'Take photo'}
            busy={captureState.capturing} disabled={captureDisabled} onPress={() => void capture()} />
          <ActionButton label={switching ? 'Switching camera…' : canSwitch ? `Use ${otherPosition} camera` : 'Only one camera available'}
            secondary disabled={!canSwitch || captureState.capturing || switching} onPress={switchCamera} />
        </View>
      </ScrollView>
      {captureState.reviewVisible && captureState.photo != null && (
        <PhotoReview photo={captureState.photo} onClose={closeReview} />
      )}
    </SafeAreaView>
  )
}

function ActionButton({ label, onPress, disabled = false, busy = false, secondary = false }: {
  label: string; onPress: () => void; disabled?: boolean; busy?: boolean; secondary?: boolean
}) {
  return (
    <Pressable onPress={onPress} disabled={disabled} accessibilityRole="button"
      accessibilityState={{ disabled, busy }}
      style={({ pressed }) => [styles.action, secondary && styles.secondaryAction,
        disabled && styles.disabled, pressed && styles.pressed]}>
      {busy && <ActivityIndicator color={secondary ? '#ffffff' : '#08120d'} size="small" />}
      <Text style={[styles.actionText, secondary && styles.secondaryActionText]}>{label}</Text>
    </Pressable>
  )
}

function PhotoReview({ photo, onClose }: { photo: CapturedPhoto; onClose: () => void }) {
  const [imageState, setImageState] = useState<'loading' | 'ready' | 'failed'>('loading')
  const [imageKey, setImageKey] = useState(0)
  return (
    <Modal visible animationType="slide" presentationStyle="fullScreen" onRequestClose={onClose}>
      <SafeAreaProvider>
        <SafeAreaView style={styles.review}>
          <StatusBar barStyle="light-content" />
          <ScrollView contentContainerStyle={styles.liveContent} alwaysBounceVertical={false}>
            <View style={styles.reviewHeader}>
              <Text style={styles.successLabel}>✓ PHOTO CAPTURED</Text>
              <Text style={styles.title} accessibilityRole="header">Your photo</Text>
              <Text style={styles.device}>
                Photo {photo.number} · {photo.position === 'front' ? 'Front' : 'Back'} camera · {photo.width} × {photo.height}
              </Text>
            </View>
            <View style={styles.reviewImage}>
              <Image key={imageKey} source={{ uri: photo.uri }} style={StyleSheet.absoluteFill} resizeMode="contain"
                accessibilityLabel={`Captured photo ${photo.number}`} accessible
                onLoad={() => {
                  setImageState('ready')
                  console.info(`[CameraExample] photo ${photo.number} review loaded`)
                }}
                onError={() => setImageState('failed')} />
              {imageState !== 'ready' && <View style={styles.previewOverlay}>
                {imageState === 'loading' ? <>
                  <ActivityIndicator color="#8df7c1" size="large" />
                  <Text style={styles.overlayTitle}>Opening photo…</Text>
                </> : <>
                  <Text style={styles.overlayTitle} accessibilityRole="alert">Preview unavailable</Text>
                  <Text style={styles.overlayDetail}>The camera captured the photo, but its image could not be loaded.</Text>
                  <ActionButton label="Reload photo" onPress={() => { setImageState('loading'); setImageKey((key) => key + 1) }} />
                </>}
              </View>}
            </View>
            <View style={styles.footer}>
              <Text style={styles.hint}>This is the captured image, not the live feed. It is stored in the app’s temporary files, not your photo library.</Text>
              <ActionButton label="Back to camera" onPress={onClose} />
            </View>
          </ScrollView>
        </SafeAreaView>
      </SafeAreaProvider>
    </Modal>
  )
}

function CenteredMessage({
  title,
  detail,
  children,
}: {
  title: string
  detail: string
  children?: React.ReactNode
}) {
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView contentContainerStyle={styles.messageContainer}>
        <Text style={styles.eyebrow}>CAMRELAY EXPO</Text>
        <Text style={styles.messageTitle} accessibilityRole="header">{title}</Text>
        <Text style={styles.messageDetail}>{detail}</Text>
        {children}
      </ScrollView>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  liveContent: {
    flexGrow: 1,
  },
  container: {
    flex: 1,
    backgroundColor: '#05070a',
    paddingHorizontal: 20,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 16,
    gap: 12,
  },
  heading: {
    flex: 1,
  },
  count: {
    color: '#cbd5e1',
    fontSize: 13,
    fontWeight: '600',
    backgroundColor: '#18202b',
    borderRadius: 14,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  viewfinder: {
    flex: 1,
    minHeight: 220,
    backgroundColor: '#000000',
    borderRadius: 20,
    overflow: 'hidden',
    borderColor: '#26313f',
    borderWidth: 1,
  },
  previewBadge: {
    alignSelf: 'flex-start',
    margin: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
    paddingHorizontal: 10,
    paddingVertical: 7,
    borderRadius: 12,
    backgroundColor: 'rgba(5, 7, 10, 0.85)',
  },
  badgeText: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: '600',
  },
  liveDot: {
    width: 7,
    height: 7,
    borderRadius: 4,
    backgroundColor: '#8df7c1',
  },
  previewOverlay: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(5, 7, 10, 0.88)',
    padding: 24,
    gap: 14,
  },
  overlayTitle: {
    color: '#ffffff',
    fontSize: 18,
    fontWeight: '700',
    textAlign: 'center',
  },
  overlayDetail: {
    color: '#cbd5e1',
    fontSize: 14,
    textAlign: 'center',
  },
  eyebrow: {
    color: '#8df7c1',
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 2,
  },
  title: {
    marginTop: 4,
    color: '#ffffff',
    fontSize: 24,
    fontWeight: '700',
  },
  device: {
    marginTop: 4,
    color: '#cbd5e1',
    fontSize: 13,
  },
  footer: {
    gap: 12,
    paddingVertical: 16,
  },
  cameraStatus: {
    color: '#a8b5c5',
    fontSize: 12,
    textAlign: 'center',
  },
  lastPhoto: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    backgroundColor: '#111923',
    borderColor: '#26313f',
    borderWidth: 1,
    borderRadius: 14,
    padding: 10,
  },
  thumbnail: {
    width: 52,
    height: 52,
    borderRadius: 8,
    backgroundColor: '#000000',
  },
  lastPhotoTitle: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '600',
  },
  linkText: {
    color: '#8df7c1',
    fontSize: 14,
    fontWeight: '600',
  },
  hint: {
    color: '#cbd5e1',
    fontSize: 13,
    lineHeight: 18,
  },
  error: {
    color: '#ffb4b4',
    fontSize: 13,
    lineHeight: 18,
  },
  errorCard: {
    backgroundColor: '#311c24',
    borderRadius: 14,
    padding: 12,
    gap: 4,
  },
  errorTitle: {
    color: '#ffb4b4',
    fontSize: 15,
    fontWeight: '700',
  },
  action: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 10,
    borderRadius: 16,
    minHeight: 52,
    backgroundColor: '#8df7c1',
    paddingHorizontal: 18,
    paddingVertical: 15,
  },
  secondaryAction: {
    backgroundColor: '#18202b',
    borderWidth: 1,
    borderColor: '#334155',
  },
  secondaryActionText: {
    color: '#ffffff',
  },
  disabled: {
    opacity: 0.4,
  },
  pressed: {
    opacity: 0.7,
  },
  actionText: {
    color: '#08120d',
    fontSize: 16,
    fontWeight: '800',
  },
  messageContainer: {
    flexGrow: 1,
    justifyContent: 'center',
    gap: 16,
    padding: 16,
  },
  messageTitle: {
    color: '#ffffff',
    fontSize: 26,
    fontWeight: '800',
    textAlign: 'center',
  },
  messageDetail: {
    color: '#cbd5e1',
    fontSize: 16,
    lineHeight: 23,
    textAlign: 'center',
  },
  review: {
    flex: 1,
    backgroundColor: '#05070a',
    paddingHorizontal: 20,
  },
  reviewHeader: {
    gap: 4,
    paddingVertical: 20,
  },
  successLabel: {
    color: '#8df7c1',
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 1,
  },
  reviewImage: {
    flex: 1,
    minHeight: 220,
    borderRadius: 20,
    backgroundColor: '#000000',
    overflow: 'hidden',
  },
})
