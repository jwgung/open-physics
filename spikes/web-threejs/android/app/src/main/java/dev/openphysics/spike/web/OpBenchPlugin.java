package dev.openphysics.spike.web;

import android.util.Log;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/** Writes one OPBENCH JSON line to logcat tag OPBENCH (benchmark-spec section 6). */
@CapacitorPlugin(name = "OpBench")
public class OpBenchPlugin extends Plugin {
    private static final String TAG = "OPBENCH";

    @PluginMethod(returnType = PluginMethod.RETURN_NONE)
    public void log(PluginCall call) {
        String line = call.getString("line");
        if (line != null) Log.i(TAG, line);
    }
}
