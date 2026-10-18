import timing from "../production/timing.json";
export const T = timing;
export const at = (id: string) => {
  const a = T.actions.find((a) => a.id === id);
  if (!a) throw new Error(id);
  return a.frame;
};
export const start = (id: string) => T.scenes.find((s) => s.id === id)!.start;
