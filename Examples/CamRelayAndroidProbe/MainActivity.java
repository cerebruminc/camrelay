package org.camrelay.androidprobe;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.media.Image;
import android.media.ImageReader;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.util.AtomicFile;
import android.util.Log;
import android.util.Size;
import android.view.Surface;
import android.view.TextureView;
import android.view.WindowManager;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import org.json.JSONObject;

/** Independent Camera2 consumer. It knows nothing about relays or fixtures. */
public final class MainActivity extends Activity {
    private HandlerThread thread;
    private Handler handler;
    private CameraDevice camera;
    private CameraCaptureSession session;
    private ImageReader reader;
    private TextureView preview;
    private Surface previewSurface;
    private long generation;
    private long frames;
    private long lastReport;
    private String lens;
    private String cameraID;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        thread = new HandlerThread("Camera2Probe");
        thread.start();
        handler = new Handler(thread.getLooper());
        preview = new TextureView(this);
        preview.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
            @Override public void onSurfaceTextureAvailable(SurfaceTexture texture, int width, int height) {
                if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) openRequestedCamera();
            }
            @Override public void onSurfaceTextureSizeChanged(SurfaceTexture texture, int width, int height) {}
            @Override public void onSurfaceTextureUpdated(SurfaceTexture texture) {}
            @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) {
                handler.post(() -> { generation++; closeCamera(); });
                return true;
            }
        });
        setContentView(preview);
    }

    @Override public void onResume() {
        super.onResume();
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] {Manifest.permission.CAMERA}, 1);
        } else {
            openRequestedCamera();
        }
    }

    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) openRequestedCamera();
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        openRequestedCamera();
    }

    @Override public void onPause() {
        handler.post(() -> { generation++; closeCamera(); });
        super.onPause();
    }

    @Override public void onDestroy() {
        thread.quitSafely();
        super.onDestroy();
    }

    private void openRequestedCamera() {
        if (!preview.isAvailable()) return;
        String requested = getIntent().getStringExtra("lens");
        SurfaceTexture texture = preview.getSurfaceTexture();
        handler.post(() -> openCamera("back".equals(requested) ? "back" : "front", texture));
    }

    private void openCamera(String requested, SurfaceTexture texture) {
        // Lifecycle callbacks can request the same active camera more than once.
        if (reader != null && requested.equals(lens)) return;
        final long current = ++generation;
        closeCamera();
        lens = requested;
        cameraID = "";
        frames = 0;
        lastReport = 0;
        report(null, "", 0);
        try {
            CameraManager manager = (CameraManager) getSystemService(CAMERA_SERVICE);
            int facing = "back".equals(lens) ? CameraCharacteristics.LENS_FACING_BACK
                : CameraCharacteristics.LENS_FACING_FRONT;
            CameraCharacteristics characteristics = null;
            for (String id : manager.getCameraIdList()) {
                CameraCharacteristics candidate = manager.getCameraCharacteristics(id);
                Integer position = candidate.get(CameraCharacteristics.LENS_FACING);
                if (position != null && position == facing) { cameraID = id; characteristics = candidate; break; }
            }
            if (characteristics == null) throw new IllegalStateException("No " + lens + " camera available");
            Size[] sizes = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                .getOutputSizes(ImageFormat.YUV_420_888);
            if (sizes == null || sizes.length == 0) throw new IllegalStateException("No YUV camera output");
            Size size = sizes[0];
            for (Size candidate : sizes) {
                if (candidate.getWidth() * candidate.getHeight() < size.getWidth() * size.getHeight()) size = candidate;
                if (candidate.getWidth() == 640 && candidate.getHeight() == 480) { size = candidate; break; }
            }
            final ImageReader output = ImageReader.newInstance(size.getWidth(), size.getHeight(), ImageFormat.YUV_420_888, 2);
            reader = output;
            texture.setDefaultBufferSize(size.getWidth(), size.getHeight());
            final Surface display = new Surface(texture);
            previewSurface = display;
            output.setOnImageAvailableListener(source -> {
                try (Image image = source.acquireLatestImage()) {
                    if (image == null || current != generation) return;
                    frames++;
                    long now = SystemClock.elapsedRealtime();
                    if (now - lastReport < 200) return;
                    lastReport = now;
                    StringBuilder samples = new StringBuilder();
                    for (int y = 1; y <= 5; y++) {
                        for (int x = 1; x <= 5; x++) {
                            // Sample cell centers to avoid aliasing regular image edges.
                            samples.append(color(image, image.getWidth() * (2 * x - 1) / 10,
                                image.getHeight() * (2 * y - 1) / 10));
                        }
                    }
                    report(null, samples.toString(), image.getTimestamp());
                } catch (Exception error) {
                    if (current == generation) report(error.toString(), "", 0);
                }
            }, handler);
            manager.openCamera(cameraID, new CameraDevice.StateCallback() {
                @Override public void onOpened(CameraDevice device) {
                    if (current != generation) { device.close(); return; }
                    camera = device;
                    try {
                        device.createCaptureSession(Arrays.asList(display, output.getSurface()),
                            new CameraCaptureSession.StateCallback() {
                                @Override public void onConfigured(CameraCaptureSession configured) {
                                    if (current != generation) { configured.close(); return; }
                                    session = configured;
                                    try {
                                        CaptureRequest.Builder request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
                                        request.addTarget(output.getSurface());
                                        request.addTarget(display);
                                        configured.setRepeatingRequest(request.build(), null, handler);
                                    } catch (Exception error) { report(error.toString(), "", 0); }
                                }
                                @Override public void onConfigureFailed(CameraCaptureSession failed) {
                                    if (current == generation) report("Camera session configuration failed", "", 0);
                                }
                            }, handler);
                    } catch (Exception error) { report(error.toString(), "", 0); }
                }
                @Override public void onDisconnected(CameraDevice device) {
                    device.close();
                    if (current == generation) report("Camera disconnected", "", 0);
                }
                @Override public void onError(CameraDevice device, int error) {
                    device.close();
                    if (current == generation) report("Camera error " + error, "", 0);
                }
            }, handler);
        } catch (Exception error) { report(error.toString(), "", 0); }
    }

    private void closeCamera() {
        if (session != null) { session.close(); session = null; }
        if (camera != null) { camera.close(); camera = null; }
        if (reader != null) { reader.close(); reader = null; }
        if (previewSurface != null) { previewSurface.release(); previewSurface = null; }
    }

    private static int sample(Image.Plane plane, int x, int y) {
        return plane.getBuffer().get(y * plane.getRowStride() + x * plane.getPixelStride()) & 255;
    }

    private static char color(Image image, int x, int y) {
        Image.Plane[] planes = image.getPlanes();
        int luma = Math.max(0, sample(planes[0], x, y) - 16);
        int u = sample(planes[1], x / 2, y / 2) - 128;
        int v = sample(planes[2], x / 2, y / 2) - 128;
        int r = (298 * luma + 409 * v + 128) >> 8;
        int g = (298 * luma - 100 * u - 208 * v + 128) >> 8;
        int b = (298 * luma + 516 * u + 128) >> 8;
        if (r > 150 && g < 100 && b < 100) return 'R';
        if (g > 150 && r < 100 && b < 100) return 'G';
        if (b > 150 && r < 100 && g < 100) return 'B';
        if (r > 180 && g > 180 && b > 180) return 'W';
        if (r < 70 && g < 70 && b < 70) return 'K';
        return '?';
    }

    private void report(String error, String samples, long timestamp) {
        AtomicFile file = new AtomicFile(new File(getFilesDir(), "status.json"));
        FileOutputStream stream = null;
        try {
            JSONObject status = new JSONObject().put("lens", lens).put("cameraID", cameraID)
                .put("frames", frames).put("timestampNs", timestamp).put("samples", samples)
                .put("error", error == null ? JSONObject.NULL : error);
            stream = file.startWrite();
            stream.write(status.toString().getBytes(StandardCharsets.UTF_8));
            file.finishWrite(stream);
            if (error != null) Log.e("CamRelayAndroidProbe", error);
        } catch (Exception failure) {
            if (stream != null) file.failWrite(stream);
            Log.e("CamRelayAndroidProbe", "Could not write frame report", failure);
        }
    }
}
