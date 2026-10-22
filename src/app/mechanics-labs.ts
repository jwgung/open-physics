import type { PlaygroundPreset } from "./physics-playground";
import type { PhysicsTermDefinition } from "./subjects/subject-experience";
// Lab texts live in one JSON file shared with the 3D app (apps/lab3d/README.md "콘텐츠 공유").
import { labs as sharedLabs } from "../../apps/lab3d/content/mechanics-labs.json";

export type LabControl = "mass" | "material" | "gravity" | "velocity";
export type LabActivationSource = "initial" | "selection";

export function shouldAutoPlayLab(_source: LabActivationSource): boolean {
  return true;
}

export interface MechanicsLab {
  readonly id: PlaygroundPreset;
  readonly title: string;
  readonly category: "움직임과 힘" | "회전과 연결" | "중력과 유체";
  readonly icon: string;
  readonly question: string;
  readonly steps: readonly [string, string, string];
  readonly observe: string;
  readonly terms: readonly PhysicsTermDefinition[];
  readonly controls: readonly LabControl[];
  readonly law: {
    readonly title: string;
    readonly description: string;
    readonly equation: string;
  };
}

/** Shape of one lab in the shared content file (apps/lab3d/content/mechanics-labs.json). */
interface SharedLabContent {
  readonly id: string;
  readonly title: string;
  readonly category: string;
  readonly icon: string;
  readonly question: string;
  readonly steps: readonly string[];
  readonly observe: string;
  readonly terms: readonly PhysicsTermDefinition[];
  readonly law: MechanicsLab["law"];
  readonly web: { readonly controls: readonly string[]; readonly tip: string };
}

const CATEGORIES: readonly MechanicsLab["category"][] = ["움직임과 힘", "회전과 연결", "중력과 유체"];
const CONTROLS: readonly LabControl[] = ["mass", "material", "gravity", "velocity"];
const PRESETS: readonly PlaygroundPreset[] = [
  "free-fall", "projectile", "collision", "spring", "friction", "rotation", "orbit", "buoyancy", "constraints", "pulley",
];

/**
 * Reads the shared lab content (the web 2D and the 3D app read the same file) into the web's lab
 * definitions, checking the parts the web relies on (preset ids, categories, three steps, controls).
 */
export function parseMechanicsLabs(labs: readonly SharedLabContent[]): MechanicsLab[] {
  return labs.map((lab) => {
    if (!PRESETS.includes(lab.id as PlaygroundPreset)) throw new RangeError(`Unknown mechanics lab: ${lab.id}`);
    if (!CATEGORIES.includes(lab.category as MechanicsLab["category"])) throw new RangeError(`Unknown category: ${lab.category}`);
    if (lab.steps.length !== 3) throw new RangeError(`${lab.id} needs three steps`);
    const controls = lab.web.controls.map((control) => {
      if (!CONTROLS.includes(control as LabControl)) throw new RangeError(`Unknown control: ${control}`);
      return control as LabControl;
    });
    return {
      id: lab.id as PlaygroundPreset,
      title: lab.title,
      category: lab.category as MechanicsLab["category"],
      icon: lab.icon,
      question: lab.question,
      steps: [lab.steps[0], lab.steps[1], lab.steps[2]],
      observe: lab.observe,
      terms: lab.terms.map((term) => ({ name: term.name, description: term.description })),
      controls,
      law: { title: lab.law.title, description: lab.law.description, equation: lab.law.equation },
    };
  });
}

export const MECHANICS_LABS: readonly MechanicsLab[] = parseMechanicsLabs(sharedLabs);

export function mechanicsLab(id: PlaygroundPreset): MechanicsLab {
  const lab = MECHANICS_LABS.find((candidate) => candidate.id === id);
  if (!lab) throw new RangeError(`Unknown mechanics lab: ${id}`);
  return lab;
}

const interactionTips = Object.fromEntries(
  sharedLabs.map((lab) => [lab.id, lab.web.tip]),
) as Record<PlaygroundPreset, string>;

export function mechanicsInteractionTip(id: PlaygroundPreset): string {
  return interactionTips[id];
}

const settingLabels: Record<LabControl, string> = {
  mass: "무게",
  material: "재질",
  gravity: "중력",
  velocity: "운동 방향",
};

export function mechanicsSettingFeedback(setting: LabControl, valueLabel: string): string {
  return `✓ ${settingLabels[setting]}: ${valueLabel} — 움직임과 그래프에 바로 반영됐어요.`;
}
