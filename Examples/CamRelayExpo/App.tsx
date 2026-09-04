import { useEffect, useState } from 'react'
import {
  ActivityIndicator,
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native'
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context'
import {
  Camera,
  type CameraPosition,
  type CameraRuntimeError,
  useCameraDevice,
  useCameraPermission,
} from 'react-native-vision-camera'

export default function App() {
  return (
    <SafeAreaProvider>
      <CameraExample />
    </SafeAreaProvider>
  )
}

function CameraExample() {
  const [position, setPosition] = useState<CameraPosition>('front')
  const [initialized, setInitialized] = useState(false)
  const [previewStarted, setPreviewStarted] = useState(false)
  const [cameraError, setCameraError] = useState<CameraRuntimeError>()
  const device = useCameraDevice(position)
  const { hasPermission, requestPermission } = useCameraPermission()

  useEffect(() => {
    if (!hasPermission) {
      void requestPermission()
    }
  }, [hasPermission, requestPermission])

  const switchCamera = () => {
    setInitialized(false)
    setPreviewStarted(false)
    setCameraError(undefined)
    setPosition((current) => (current === 'front' ? 'back' : 'front'))
  }

  if (!hasPermission) {
    return (
      <CenteredMessage
        title="Camera permission required"
        detail="Grant camera permission, then relaunch the example while CamRelay is active."
      >
        <Pressable style={styles.action} onPress={() => void requestPermission()}>
          <Text style={styles.actionText}>Grant permission</Text>
        </Pressable>
      </CenteredMessage>
    )
  }

  if (device == null) {
    return (
      <CenteredMessage
        title="No camera discovered"
        detail="Start CamRelay, then relaunch this app so it inherits the Simulator-wide camera runtime."
      />
    )
  }

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" />
      <Camera
        style={StyleSheet.absoluteFill}
        device={device}
        isActive
        onError={setCameraError}
        onInitialized={() => setInitialized(true)}
        onPreviewStarted={() => setPreviewStarted(true)}
        onPreviewStopped={() => setPreviewStarted(false)}
      />

      <SafeAreaView style={styles.overlay} pointerEvents="box-none">
        <View style={styles.header} pointerEvents="none">
          <Text style={styles.eyebrow}>CAMRELAY EXPO</Text>
          <Text style={styles.title}>VisionCamera preview</Text>
          <Text style={styles.device}>{device.name}</Text>
        </View>

        <View style={styles.footer}>
          <View style={styles.statusCard} pointerEvents="none">
            <StatusRow label="Camera" active={initialized} />
            <StatusRow label="Preview" active={previewStarted} />
            <Text style={cameraError == null ? styles.hint : styles.error}>
              {cameraError == null
                ? 'Motion in the fixture confirms that video frames are loading.'
                : `${cameraError.code}: ${cameraError.message}`}
            </Text>
          </View>

          <Pressable style={styles.action} onPress={switchCamera}>
            <Text style={styles.actionText}>Use {position === 'front' ? 'back' : 'front'} camera</Text>
          </Pressable>
        </View>
      </SafeAreaView>
    </View>
  )
}

function StatusRow({ label, active }: { label: string; active: boolean }) {
  return (
    <View style={styles.statusRow}>
      <View style={[styles.statusDot, active && styles.statusDotActive]} />
      <Text style={styles.statusText}>
        {label}: {active ? 'active' : 'starting'}
      </Text>
      {!active && <ActivityIndicator color="#ffffff" size="small" />}
    </View>
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
    <SafeAreaView style={styles.messageContainer}>
      <StatusBar barStyle="light-content" />
      <Text style={styles.eyebrow}>CAMRELAY EXPO</Text>
      <Text style={styles.messageTitle}>{title}</Text>
      <Text style={styles.messageDetail}>{detail}</Text>
      {children}
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#05070a',
  },
  overlay: {
    flex: 1,
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  header: {
    alignSelf: 'flex-start',
    borderRadius: 18,
    backgroundColor: 'rgba(5, 7, 10, 0.78)',
    paddingHorizontal: 18,
    paddingVertical: 14,
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
  },
  statusCard: {
    gap: 9,
    borderRadius: 18,
    backgroundColor: 'rgba(5, 7, 10, 0.82)',
    padding: 16,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 9,
  },
  statusDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#64748b',
  },
  statusDotActive: {
    backgroundColor: '#3df29d',
  },
  statusText: {
    flex: 1,
    color: '#ffffff',
    fontSize: 16,
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
  action: {
    alignItems: 'center',
    borderRadius: 16,
    backgroundColor: '#ffffff',
    paddingHorizontal: 18,
    paddingVertical: 15,
  },
  actionText: {
    color: '#08120d',
    fontSize: 16,
    fontWeight: '800',
  },
  messageContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    backgroundColor: '#08120d',
    paddingHorizontal: 30,
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
})
