import { PLAYGROUND_PRESETS, type PlaygroundPreset } from "./physics-playground";
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
function isPlaygroundPreset(id: string): id is PlaygroundPreset {
  return PLAYGROUND_PRESETS.some((preset) => preset === id);
}

interface ParsedLabs {
  readonly labs: MechanicsLab[];
  readonly tips: ReadonlyMap<PlaygroundPreset, string>;
}

/**
 * Reads the shared lab content (the web 2D and the 3D app read the same file) into the web's lab
 * definitions, checking the parts the web relies on (preset ids, categories, three steps, controls)
 * and that every preset has exactly one lab with an interaction tip.
 */
export function parseMechanicsLabs(labs: readonly SharedLabContent[]): MechanicsLab[] {
  return parseLabs(labs).labs;
}

function parseLabs(content: readonly SharedLabContent[]): ParsedLabs {
  const tips = new Map<PlaygroundPreset, string>();
  const labs = content.map((lab): MechanicsLab => {
    const id = lab.id;
    if (!isPlaygroundPreset(id)) throw new RangeError(`Unknown mechanics lab: ${id}`);
    if (tips.has(id)) throw new RangeError(`Duplicate mechanics lab: ${id}`);
    if (typeof lab.web.tip !== "string" || lab.web.tip.trim() === "") throw new RangeError(`${id} needs an interaction tip`);
    tips.set(id, lab.web.tip);
    if (!CATEGORIES.includes(lab.category as MechanicsLab["category"])) throw new RangeError(`Unknown category: ${lab.category}`);
    if (lab.steps.length !== 3) throw new RangeError(`${lab.id} needs three steps`);
    const controls = lab.web.controls.map((control) => {
      if (!CONTROLS.includes(control as LabControl)) throw new RangeError(`Unknown control: ${control}`);
      return control as LabControl;
    });
    return {
      id,
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
  const missing = PLAYGROUND_PRESETS.filter((preset) => !tips.has(preset));
  if (missing.length > 0) throw new RangeError(`Missing mechanics labs: ${missing.join(", ")}`);
  return { labs, tips };
}

const SHARED_LABS = parseLabs(sharedLabs);

export const MECHANICS_LABS: readonly MechanicsLab[] = SHARED_LABS.labs;

export function mechanicsLab(id: PlaygroundPreset): MechanicsLab {
  const lab = MECHANICS_LABS.find((candidate) => candidate.id === id);
  if (!lab) throw new RangeError(`Unknown mechanics lab: ${id}`);
  return lab;
}

export function mechanicsInteractionTip(id: PlaygroundPreset): string {
  const tip = SHARED_LABS.tips.get(id);
  if (tip === undefined) throw new RangeError(`Unknown mechanics lab: ${id}`);
  return tip;
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
