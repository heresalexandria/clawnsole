package ai.clawnsole.reference_video_tools;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.antonkarpenko.ffmpegkit.FFmpegKit;
import com.antonkarpenko.ffmpegkit.FFprobeKit;
import com.antonkarpenko.ffmpegkit.ReturnCode;
import com.antonkarpenko.ffmpegkit.Session;

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

    private void reply(Session session, MethodChannel.Result result) {
        final ReturnCode returnCode = session.getReturnCode();
        final Map<String, Object> response = new HashMap<>();
        response.put("exitCode", returnCode == null ? -1 : returnCode.getValue());
        response.put("output", session.getOutput() == null ? "" : session.getOutput());
        mainHandler.post(() -> result.success(response));
    }
}
