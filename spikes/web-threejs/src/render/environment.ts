import { PMREMGenerator, type Scene, type Texture, type WebGPURenderer } from "three/webgpu";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

/** Procedural room IBL so metal/PBR materials have something to reflect (no HDR asset). */
export function applyRoomEnvironment(renderer: WebGPURenderer, scene: Scene): Texture {
  const generator = new PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  const texture = generator.fromScene(room, 0.04).texture;
  room.dispose();
  generator.dispose();
  scene.environment = texture;
  scene.environmentIntensity = 0.6;
  return texture;
}
