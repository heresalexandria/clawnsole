package ai.clawnsole.reference_video_tools;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.ColorSpace;
import android.graphics.ImageDecoder;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.antonkarpenko.ffmpegkit.FFmpegKit;
import com.antonkarpenko.ffmpegkit.FFprobeKit;
import com.antonkarpenko.ffmpegkit.ReturnCode;
import com.antonkarpenko.ffmpegkit.Session;

import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class ReferenceVideoToolsPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private MethodChannel channel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(
                binding.getBinaryMessenger(),
                "ai.clawnsole/reference_video_tools");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(
            @NonNull MethodCall call,
            @NonNull MethodChannel.Result result) {
        if ("convertImageToJpeg".equals(call.method)) {
            final String inputPath = call.argument("inputPath");
            final String outputPath = call.argument("outputPath");
            if (inputPath == null || outputPath == null) {
                result.error("invalid_arguments", "Image conversion paths are missing.", null);
                return;
            }
            new Thread(
                    () -> convertImageToJpeg(inputPath, outputPath, result),
                    "clawnsole-image-conversion")
                    .start();
            return;
        }
        if (!"execute".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final List<?> rawArguments = call.argument("arguments");
        final Boolean probe = call.argument("probe");
        if (rawArguments == null || probe == null) {
            result.error("invalid_arguments", "Media tool arguments are missing.", null);
            return;
        }
        final List<String> arguments = new ArrayList<>(rawArguments.size());
        for (Object value : rawArguments) {
            if (!(value instanceof String)) {
                result.error("invalid_arguments", "Media tool arguments must be strings.", null);
                return;
            }
            arguments.add((String) value);
        }
        try {
            if (probe) {
                FFprobeKit.executeWithArgumentsAsync(
                        arguments.toArray(new String[0]),
                        session -> reply(session, result));
            } else {
                FFmpegKit.executeWithArgumentsAsync(
                        arguments.toArray(new String[0]),
                        session -> reply(session, result));
            }
        } catch (Throwable error) {
            result.error("media_tool_failed", error.getMessage(), null);
        }
    }

    private void convertImageToJpeg(
            String inputPath,
            String outputPath,
            MethodChannel.Result result) {
        int exitCode = -1;
        String output = "";
        Bitmap decoded = null;
        Bitmap rendered = null;
        final File destination = new File(outputPath);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                final ImageDecoder.Source source = ImageDecoder.createSource(new File(inputPath));
                decoded = ImageDecoder.decodeBitmap(source, (decoder, info, ignored) -> {
                    decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
                    decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB));
                });
            } else {
                decoded = BitmapFactory.decodeFile(inputPath);
            }
            if (decoded == null || decoded.getWidth() <= 0 || decoded.getHeight() <= 0) {
                throw new IllegalStateException(
                        "The primary reference image could not be decoded.");
            }

            // Render the complete, orientation-correct primary bitmap into an
            // sRGB canvas of identical dimensions. This never crops or scales.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                rendered = Bitmap.createBitmap(
                        decoded.getWidth(),
                        decoded.getHeight(),
                        Bitmap.Config.ARGB_8888,
                        true,
                        ColorSpace.get(ColorSpace.Named.SRGB));
            } else {
                rendered = Bitmap.createBitmap(
                        decoded.getWidth(), decoded.getHeight(), Bitmap.Config.ARGB_8888);
            }
            new Canvas(rendered).drawBitmap(decoded, 0, 0, null);
            try (FileOutputStream stream = new FileOutputStream(destination)) {
                if (!rendered.compress(Bitmap.CompressFormat.JPEG, 94, stream)) {
                    throw new IllegalStateException(
                            "The normalized reference image could not be saved.");
                }
                stream.flush();
            }
            exitCode = 0;
        } catch (Throwable error) {
            destination.delete();
            output = error.getMessage() == null
                    ? "The reference image could not be converted to JPEG."
                    : error.getMessage();
        } finally {
            if (rendered != null && rendered != decoded) {
                rendered.recycle();
            }
            if (decoded != null) {
                decoded.recycle();
            }
        }

        final Map<String, Object> response = new HashMap<>();
        response.put("exitCode", exitCode);
        response.put("output", output);
        mainHandler.post(() -> result.success(response));
    }

    private void reply(Session session, MethodChannel.Result result) {
        final ReturnCode returnCode = session.getReturnCode();
        final Map<String, Object> response = new HashMap<>();
        response.put("exitCode", returnCode == null ? -1 : returnCode.getValue());
        response.put("output", session.getOutput() == null ? "" : session.getOutput());
        mainHandler.post(() -> result.success(response));
    }
}
