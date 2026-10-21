import { PMREMGenerator as NodePMREMGenerator, type Scene, type Texture, type WebGPURenderer } from "three/webgpu";
import { PMREMGenerator as ClassicPMREMGenerator, type WebGLRenderer } from "three";
import type { AnyRenderer } from "../scenes/types";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

/** Procedural room IBL so metal/PBR materials have something to reflect (no HDR asset). */
export function applyRoomEnvironment(renderer: AnyRenderer, scene: Scene): Texture {
  const generator = "isWebGLRenderer" in renderer
    ? new ClassicPMREMGenerator(renderer as WebGLRenderer)
    : new NodePMREMGenerator(renderer as WebGPURenderer);
  const room = new RoomEnvironment();
  const texture = generator.fromScene(room, 0.04).texture;
  room.dispose();
  generator.dispose();
  scene.environment = texture;
  scene.environmentIntensity = 0.6;
  return texture;
}
