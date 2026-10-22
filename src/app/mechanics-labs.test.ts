import { describe, expect, it } from "vitest";
import sharedContent from "../../apps/lab3d/content/mechanics-labs.json";
import {
  MECHANICS_LABS,
  mechanicsInteractionTip,
  mechanicsLab,
  mechanicsSettingFeedback,
  parseMechanicsLabs,
  shouldAutoPlayLab,
} from "./mechanics-labs";

describe("mechanics labs", () => {
  it("defines ten distinct experiments with actionable learning content", () => {
    expect(MECHANICS_LABS).toHaveLength(10);
    expect(new Set(MECHANICS_LABS.map((lab) => lab.id)).size).toBe(10);
    for (const lab of MECHANICS_LABS) {
      expect(lab.question.endsWith("까요?")).toBe(true);
      expect(lab.steps).toHaveLength(3);
      expect(lab.steps.every((step) => step.length >= 10)).toBe(true);
      expect(lab.observe.length).toBeGreaterThan(20);
      expect(lab.terms.length).toBeGreaterThanOrEqual(3);
      expect(lab.terms.every((term) => term.name.length >= 2 && term.description.length >= 12)).toBe(true);
      expect(lab.controls.length).toBeGreaterThan(0);
      expect(lab.law.title.length).toBeGreaterThan(1);
      expect(lab.law.description.length).toBeGreaterThan(10);
      expect(lab.law.equation.length).toBeGreaterThan(2);
    }
  });

  it("exposes only controls that change the selected experiment", () => {
    expect(mechanicsLab("pulley").controls).toEqual(["mass"]);
    expect(mechanicsLab("orbit").controls).toEqual(["velocity"]);
    expect(mechanicsLab("friction").controls).toContain("material");
    expect(mechanicsLab("free-fall").controls).toContain("gravity");
  });

  it("auto-plays a dedicated lab consistently whether it was selected or opened by URL", () => {
    expect(shouldAutoPlayLab("initial")).toBe(true);
    expect(shouldAutoPlayLab("selection")).toBe(true);
  });

  it("keeps the direct manipulation target visible for every guided experiment", () => {
    for (const lab of MECHANICS_LABS) {
      expect(mechanicsInteractionTip(lab.id).length).toBeGreaterThan(12);
    }
    expect(mechanicsInteractionTip("friction")).toContain("빨간 손잡이");
    expect(mechanicsInteractionTip("rotation")).toContain("힘점");
    expect(mechanicsInteractionTip("pulley")).toContain("아래로");
    expect(mechanicsInteractionTip("orbit")).toContain("보라색 화살표");
  });

  it("explains immediately what a changed condition affects", () => {
    expect(mechanicsSettingFeedback("mass", "가벼움")).toContain("무게: 가벼움");
    expect(mechanicsSettingFeedback("material", "나무")).toContain("움직임과 그래프");
    expect(mechanicsSettingFeedback("gravity", "달 · 0.17×")).toContain("중력: 달 · 0.17×");
  });

  it("reads the shared content file without changing a single text (Task 4a)", async () => {
    // SHA-256 of the labs and interaction tips as they were written in this file before the texts
    // moved to apps/lab3d/content/mechanics-labs.json (commit 4cb04a4). Any change to a web text,
    // its order or a control fails here.
    const payload = JSON.stringify({
      labs: MECHANICS_LABS,
      tips: MECHANICS_LABS.map((lab) => [lab.id, mechanicsInteractionTip(lab.id)]),
    });
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(payload));
    expect([...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join(""))
      .toBe("9fcf3b93d11e3918584cf22eecdba3748b6aa16adcf82018e16de335bd69f340");
    expect(sharedContent.labs.map((lab) => lab.id)).toEqual(MECHANICS_LABS.map((lab) => lab.id));
  });

  it("rejects shared content the web cannot show", () => {
    const labs = sharedContent.labs;
    const lab = labs[0];
    const withFirst = (changed: (typeof labs)[number]) => [changed, ...labs.slice(1)];
    expect(parseMechanicsLabs(labs)).toEqual(MECHANICS_LABS);
    expect(() => parseMechanicsLabs(withFirst({ ...lab, id: "sandbox" }))).toThrow(/Unknown mechanics lab: sandbox/);
    expect(() => parseMechanicsLabs(withFirst({ ...lab, category: "열" }))).toThrow(/Unknown category/);
    expect(() => parseMechanicsLabs(withFirst({ ...lab, steps: lab.steps.slice(0, 2) }))).toThrow(/three steps/);
    expect(() => parseMechanicsLabs(withFirst({ ...lab, web: { ...lab.web, controls: ["speed"] } }))).toThrow(/Unknown control/);
    // Every preset needs its lab and its interaction tip (the web shows both).
    expect(() => parseMechanicsLabs(labs.slice(1))).toThrow(new RangeError(`Missing mechanics labs: ${lab.id}`));
    expect(() => parseMechanicsLabs(withFirst({ ...lab, web: { ...lab.web, tip: "" } }))).toThrow(`${lab.id} needs an interaction tip`);
    expect(() => parseMechanicsLabs([...labs, lab])).toThrow(`Duplicate mechanics lab: ${lab.id}`);
  });
});
