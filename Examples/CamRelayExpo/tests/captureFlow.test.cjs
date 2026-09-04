const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const { test } = require('node:test')
const ts = require('typescript')

// Run the pure TypeScript state model without a native camera or extra test dependencies.
const source = fs.readFileSync(path.join(__dirname, '../captureFlow.ts'), 'utf8')
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } })
const model = { exports: {} }
vm.runInNewContext(compiled.outputText, model)
const { captureReducer: reduce, initialCaptureState: initial, photoURI } = model.exports
const result = { type: 'success', path: '/tmp/photo.jpg', width: 320, height: 240, position: 'front' }
const captured = () => reduce(reduce(initial, { type: 'start' }), result)

test('accepts both native file paths and existing file URLs', () => {
  assert.equal(photoURI('/tmp/photo.jpg'), 'file:///tmp/photo.jpg')
  assert.equal(photoURI('file:///tmp/photo.jpg'), 'file:///tmp/photo.jpg')
})

test('capture shows busy state, then automatically opens the actual photo', () => {
  const pending = reduce(initial, { type: 'start' })
  assert.equal(pending.capturing, true)
  assert.equal(pending.reviewVisible, false)
  const done = reduce(pending, result)
  assert.equal(done.capturing, false)
  assert.equal(done.reviewVisible, true)
  assert.equal(done.count, 1)
  assert.equal(done.photo.uri, 'file:///tmp/photo.jpg')
  assert.equal(done.photo.position, 'front')
  assert.equal(done.photo.width, 320)
  assert.equal(done.photo.height, 240)
  assert.equal(done.photo.number, 1)
  assert.equal(initial.count, 0)
})

test('closing and reopening review preserves the photo and count', () => {
  const done = captured()
  assert.equal(reduce(done, { type: 'start' }), done)
  const closed = reduce(done, { type: 'close-review' })
  assert.equal(closed.reviewVisible, false)
  assert.equal(closed.photo, done.photo)
  const reopened = reduce(closed, { type: 'open-review' })
  assert.equal(reopened.reviewVisible, true)
  assert.equal(reopened.count, 1)
  assert.equal(reduce(initial, { type: 'open-review' }), initial)
})

test('another capture replaces the thumbnail and records its camera', () => {
  const pending = reduce(reduce(captured(), { type: 'close-review' }), { type: 'start' })
  const next = reduce(pending, { ...result, path: 'file:///tmp/next.jpg', position: 'back' })
  assert.equal(next.count, 2)
  assert.equal(next.photo.number, 2)
  assert.equal(next.photo.uri, 'file:///tmp/next.jpg')
  assert.equal(next.photo.position, 'back')
  assert.equal(next.reviewVisible, true)
})

test('failed capture preserves the last photo and allows retry', () => {
  const previous = reduce(captured(), { type: 'close-review' })
  const pending = reduce(previous, { type: 'start' })
  const failed = reduce(pending, { type: 'failure', message: 'Camera unavailable' })
  assert.equal(failed.capturing, false)
  assert.equal(failed.reviewVisible, false)
  assert.equal(failed.count, 1)
  assert.equal(failed.photo, previous.photo)
  assert.equal(failed.error, 'Camera unavailable')
  assert.equal(reduce(failed, { type: 'dismiss-error' }).error, undefined)
  const retry = reduce(failed, { type: 'start' })
  assert.equal(retry.error, undefined)
  assert.equal(retry.capturing, true)
})

test('duplicate actions do not double-count or interrupt a capture', () => {
  const pending = reduce(initial, { type: 'start' })
  assert.equal(reduce(pending, { type: 'start' }), pending)
  assert.equal(reduce(pending, { type: 'open-review' }), pending)
  const done = reduce(pending, result)
  assert.equal(reduce(done, result), done)
  assert.equal(reduce(done, { type: 'failure', message: 'Late error' }), done)
})
