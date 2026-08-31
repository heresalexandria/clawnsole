package ai.clawnsole.reference_video_tools;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.ColorSpace;
import android.graphics.ImageDecoder;
import android.graphics.Paint;
import android.graphics.Rect;
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
            final Number rawMaxPixels = call.argument("maxPixels");
            if (inputPath == null
                    || outputPath == null
                    || (rawMaxPixels != null && rawMaxPixels.longValue() <= 0)) {
                result.error(
                        "invalid_arguments",
                        "Image conversion paths are missing or the pixel limit is invalid.",
                        null);
                return;
            }
            final long maxPixels = rawMaxPixels == null ? 0 : rawMaxPixels.longValue();
            new Thread(
                    () -> convertImageToJpeg(inputPath, outputPath, maxPixels, result),
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
            long maxPixels,
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
                    final int[] target = constrainedDimensions(
                            info.getSize().getWidth(),
                            info.getSize().getHeight(),
                            maxPixels);
                    if (target[0] != info.getSize().getWidth()
                            || target[1] != info.getSize().getHeight()) {
                        decoder.setTargetSize(target[0], target[1]);
                    }
                });
            } else {
                final BitmapFactory.Options bounds = new BitmapFactory.Options();
                bounds.inJustDecodeBounds = true;
                BitmapFactory.decodeFile(inputPath, bounds);
                final int[] desired = constrainedDimensions(
                        bounds.outWidth, bounds.outHeight, maxPixels);
                int sampleSize = 1;
                while (bounds.outWidth / (sampleSize * 2) >= desired[0]
                        && bounds.outHeight / (sampleSize * 2) >= desired[1]) {
                    sampleSize *= 2;
                }
                final BitmapFactory.Options options = new BitmapFactory.Options();
                options.inSampleSize = sampleSize;
                decoded = BitmapFactory.decodeFile(inputPath, options);
            }
            if (decoded == null || decoded.getWidth() <= 0 || decoded.getHeight() <= 0) {
                throw new IllegalStateException(
                        "The primary reference image could not be decoded.");
            }

            final int[] target = constrainedDimensions(
                    decoded.getWidth(), decoded.getHeight(), maxPixels);

            // Render the complete, orientation-correct primary bitmap into an
            // sRGB canvas. Any size reduction is proportional and never crops.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                rendered = Bitmap.createBitmap(
                        target[0],
                        target[1],
                        Bitmap.Config.ARGB_8888,
                        true,
                        ColorSpace.get(ColorSpace.Named.SRGB));
            } else {
                rendered = Bitmap.createBitmap(
                        target[0], target[1], Bitmap.Config.ARGB_8888);
            }
            final Paint paint = new Paint(
                    Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG | Paint.DITHER_FLAG);
            new Canvas(rendered).drawBitmap(
                    decoded,
                    null,
                    new Rect(0, 0, target[0], target[1]),
                    paint);
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

    private static int[] constrainedDimensions(int width, int height, long maxPixels) {
        double scale = 1.0;
        final double sourcePixels = (double) width * (double) height;
        if (maxPixels > 0 && sourcePixels > maxPixels) {
            scale = Math.sqrt(maxPixels / sourcePixels);
        }
        return new int[] {
                Math.max(1, (int) Math.floor(width * scale)),
                Math.max(1, (int) Math.floor(height * scale)),
        };
    }

    private void reply(Session session, MethodChannel.Result result) {
        final ReturnCode returnCode = session.getReturnCode();
        final Map<String, Object> response = new HashMap<>();
        response.put("exitCode", returnCode == null ? -1 : returnCode.getValue());
        response.put("output", session.getOutput() == null ? "" : session.getOutput());
        mainHandler.post(() -> result.success(response));
    }
}
