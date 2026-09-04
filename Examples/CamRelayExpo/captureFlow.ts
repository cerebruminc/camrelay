export type CapturedPhoto = {
  uri: string
  width: number
  height: number
  position: 'front' | 'back'
  number: number
}

export type CaptureState = {
  capturing: boolean
  count: number
  photo?: CapturedPhoto
  reviewVisible: boolean
  error?: string
}

type CaptureAction =
  | { type: 'start' }
  | { type: 'success'; path: string; width: number; height: number; position: 'front' | 'back' }
  | { type: 'failure'; message: string }
  | { type: 'open-review' }
  | { type: 'close-review' }
  | { type: 'dismiss-error' }

export const initialCaptureState: CaptureState = { capturing: false, count: 0, reviewVisible: false }

export function photoURI(path: string): string {
  return path.startsWith('file://') ? path : `file://${path}`
}

export function captureReducer(state: CaptureState, action: CaptureAction): CaptureState {
  switch (action.type) {
    case 'start':
      if (state.capturing || state.reviewVisible) return state
      return { ...state, capturing: true, error: undefined }
    case 'success':
      if (!state.capturing) return state
      return {
        capturing: false,
        count: state.count + 1,
        reviewVisible: true,
        photo: {
          uri: photoURI(action.path), width: action.width, height: action.height,
          position: action.position, number: state.count + 1,
        },
      }
    case 'failure':
      if (!state.capturing) return state
      return { ...state, capturing: false, error: action.message }
    case 'open-review':
      return state.photo != null && !state.capturing ? { ...state, reviewVisible: true } : state
    case 'close-review':
      return { ...state, reviewVisible: false }
    case 'dismiss-error':
      return { ...state, error: undefined }
  }
}
