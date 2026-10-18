import React from "react";
import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from "remotion";
import { SCENES, Handoff } from "./scenes";
import { A, ease } from "./design";
import { T } from "./timeline";
import "./style.css";
export const CleanFilm: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill>
      {T.scenes.map((s, i) => {
        if (f < s.start || f >= s.start + s.duration + T.motion.enterFrames)
          return null;
        const Scene = SCENES[i];
        const incoming = i > 0 ? ease((f - s.start) / 24) : 1;
        return (
          <AbsoluteFill
            key={s.id}
            style={{
              clipPath:
                incoming < 1
                  ? `circle(${260 + incoming * 1990}px at ${A.x}px ${A.y}px)`
                  : undefined,
              filter:
                incoming > 0.05 && incoming < 0.85
                  ? `blur(${(1 - incoming) * 1.5}px)`
                  : undefined,
            }}
          >
            <Scene f={f} />
          </AbsoluteFill>
        );
      })}
      <Handoff f={f} />
      <Audio src={staticFile("audio/mix.wav")} />
    </AbsoluteFill>
  );
};
