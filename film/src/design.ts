export const C = {
  paper: "#f5f7f4",
  ink: "#14201c",
  dark: "#13171d",
  mint: "#c7e6b7",
  teal: "#4a9d83",
  white: "#ffffff",
};
export const A = { x: 1320, y: 540 };
export const ease = (x: number) =>
  1 - Math.pow(1 - Math.max(0, Math.min(1, x)), 4);
export const ramp = (f: number, start: number, d = 28) => ease((f - start) / d);
export const breathe = (f: number) => Math.sin(f / 42) * 2;
