export type BuildAssetPromptInput = {
  projectIdentity: string;
  partLabel: string;
  partPrompt: string;
  customInstructions?: string;
};

function normalizeInline(value: string): string {
  return value
    .replace(/[\u0000-\u001F\u007F]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function requiredInline(value: string, fieldName: string): string {
  const normalized = normalizeInline(value);
  if (normalized.length === 0) {
    throw new Error(`${fieldName} must not be blank or control-only.`);
  }
  return normalized;
}

function clampUnicode(value: string, maxCharacters: number): string {
  return Array.from(value).slice(0, maxCharacters).join("");
}

export function buildAssetPrompt(input: BuildAssetPromptInput): string {
  const identity = normalizeInline(input.projectIdentity);
  const partLabel = requiredInline(input.partLabel, "partLabel");
  const partPrompt = requiredInline(input.partPrompt, "partPrompt");

  const lines = [
    "Generate a clean isolated reference image of the same character.",
    `Identity: ${identity}`,
    `Requested asset: ${partLabel}`,
    `Instruction: ${partPrompt}`,
  ];

  if (input.customInstructions !== undefined) {
    const custom = requiredInline(input.customInstructions, "customInstructions");
    lines.push(`Additional instruction: ${clampUnicode(custom, 1000)}`);
  }

  lines.push(
    "Preserve identity, proportions, materials, colors, clothing design, damage, and accessories from the reference image.",
    "Show only the requested asset clearly and completely.",
  );

  return lines.join("\n");
}
