import { Composition } from "remotion";
import { CleanFilm } from "./Composition";
import { T } from "./timeline";
export const RemotionRoot = () => (
  <Composition
    id="CleanFilm"
    component={CleanFilm}
    durationInFrames={T.durationFrames}
    fps={T.fps}
    width={1920}
    height={1080}
  />
);
