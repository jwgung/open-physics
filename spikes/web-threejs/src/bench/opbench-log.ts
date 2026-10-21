/**
 * Sends OPBENCH lines to logcat tag OPBENCH.
 * Capacitor routes console.* to tag "Capacitor/Console", so on Android a tiny local
 * plugin (android/.../OpBenchPlugin.java) calls android.util.Log.i("OPBENCH", line).
 * In a browser the line is printed as "OPBENCH <json>".
 */
import { Capacitor, registerPlugin } from "@capacitor/core";
import { formatOpbench, type OpbenchLine } from "./frame-stats";

interface OpBenchPlugin {
  log(options: { line: string }): Promise<void>;
}

const OpBench = registerPlugin<OpBenchPlugin>("OpBench");
const native = Capacitor.isNativePlatform() && Capacitor.isPluginAvailable("OpBench");

export function emitOpbench(line: OpbenchLine): void {
  const json = formatOpbench(line);
  if (native) {
    void OpBench.log({ line: json }).catch(() => console.log(`OPBENCH ${json}`));
  } else {
    console.log(`OPBENCH ${json}`);
  }
}
