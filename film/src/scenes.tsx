import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { A, C, breathe, ease, ramp } from "./design";
import { at, start, T } from "./timeline";
import { Button, Check, Chrome, Cursor, Footer, Label, Topline } from "./ui";
// A motivated slow inspection move keeps UI readable while sustaining motion.
const SceneFrame: React.FC<
  React.PropsWithChildren<{
    f: number;
    scene: string;
    style: React.CSSProperties;
  }>
> = ({ f, scene, style, children }) => {
  const shot = T.scenes.find((s) => s.id === scene)!;
  const u = Math.max(0, Math.min(1, (f - shot.start) / shot.duration));
  const p = u + 0.05 * Math.sin(u * Math.PI * 2);
  const list = React.Children.toArray(children);
  const isHUD = (c: React.ReactNode) =>
    React.isValidElement(c) && (c.type === Topline || c.type === Footer);
  return (
    <AbsoluteFill style={style}>
      <AbsoluteFill
        style={{
          transform: `translate(${-10 + 20 * p}px,${8 - 16 * p}px) scale(${1.01 + 0.04 * p})`,
          transformOrigin: "50% 50%",
        }}
      >
        {list.filter((c) => !isHUD(c))}
      </AbsoluteFill>
      {list.filter(isHUD)}
    </AbsoluteFill>
  );
};
const rows = ["npm 下载缓存", "浏览器缓存", "设备备份 · 个人数据"];
const paths = [
  "~/.npm/_cacache",
  "~/Library/Caches",
  "~/Library/Application Support/MobileSync/Backup",
];
const shell = (dark = true): React.CSSProperties => ({
  background: dark ? C.dark : C.paper,
  color: dark ? C.white : C.ink,
});
const motion = (f: number) => ({ transform: `translateY(${breathe(f)}px)` });
export const Hook: React.FC<{ f: number }> = ({ f }) => (
  <SceneFrame f={f} scene="hook" style={shell(false)}>
    <div
      style={{
        position: "absolute",
        left: 130,
        top: 74,
        fontSize: 52,
        fontWeight: 650,
      }}
    >
      Clean.
    </div>
    <div style={{ position: "absolute", right: 120, top: 90, fontSize: 27 }}>
      原生 macOS 磁盘工具
    </div>
    <div
      style={{
        position: "absolute",
        left: 130,
        top: 300,
        fontSize: 108,
        lineHeight: 1.35,
        fontWeight: 650,
        ...motion(f),
      }}
    >
      先看清，
      <br />
      再动手。
    </div>
    <div style={{ position: "absolute", left: 135, top: 720, fontSize: 32 }}>
      给 Mac 一点呼吸的空间。
    </div>
    <Img
      src={staticFile("clean-icon.png")}
      style={{
        position: "absolute",
        left: A.x - 188,
        top: A.y - 188,
        width: 376,
        height: 376,
        transform: `translateY(${breathe(f + 20)}px) rotate(${-5 + Math.sin(f / 55) * 4}deg) scale(${1 + 0.055 * Math.sin(Math.min(1, f / 180) * Math.PI)})`,
      }}
    />
    <svg
      width="1920"
      height="1080"
      style={{ position: "absolute", pointerEvents: "none" }}
    >
      <circle
        cx={A.x + 260 * Math.cos(f / 55)}
        cy={A.y + 260 * Math.sin(f / 55)}
        r="10"
        fill={C.teal}
      />
    </svg>
    <Footer dark={false} />
  </SceneFrame>
);
export const Scan: React.FC<{ f: number }> = ({ f }) => {
  const local = f - start("scan");
  const done = f >= at("scanComplete");
  return (
    <SceneFrame f={f} scene="scan" style={shell()}>
      <Topline label="01 / 扫描" />
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 240,
          width: 510,
          ...motion(f),
        }}
      >
        <div style={{ fontSize: 83, fontWeight: 650, lineHeight: 1.3 }}>
          已知缓存，
          <br />
          逐项看清。
        </div>
        <div style={{ fontSize: 33, lineHeight: 1.6, marginTop: 35 }}>
          用户缓存 / 浏览器
          <br />
          Xcode / npm
        </div>
        <div style={{ fontSize: 30, lineHeight: 1.6, marginTop: 28 }}>
          扫描过程压缩演示
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 710,
          top: 225,
          width: 1090,
          transform: `translateY(${(1 - ramp(local, 0)) * 35 + breathe(f)}px)`,
        }}
      >
        <Chrome title="Clean · 清理">
          <div style={{ display: "flex", height: 570 }}>
            <div
              style={{
                width: 170,
                borderRight: `1px solid ${C.white}22`,
                padding: "35px 24px",
                fontSize: 26,
                lineHeight: 2.6,
              }}
            >
              {["概览", "清理", "卸载", "优化", "分析", "状态"].map((x) => (
                <div
                  key={x}
                  style={{
                    color: x === "清理" ? C.mint : C.white,
                    fontWeight: x === "清理" ? 700 : 400,
                  }}
                >
                  {x}
                </div>
              ))}
            </div>
            <div style={{ flex: 1, padding: "35px 30px" }}>
              <div style={{ fontSize: 40, fontWeight: 600, marginBottom: 20 }}>
                清理
              </div>
              {["Xcode 构建缓存", "npm 下载缓存", "浏览器缓存"].map((x, i) => (
                <div
                  key={x}
                  style={{
                    padding: "20px 0",
                    borderBottom: `1px solid ${C.white}22`,
                    fontSize: 31,
                    display: "flex",
                    justifyContent: "space-between",
                    opacity: ramp(local, 30 + i * 15),
                    transform: `translateX(${(1 - ramp(local, 30 + i * 15)) * 30}px)`,
                  }}
                >
                  <span>{x}</span>
                  <span style={{ color: C.mint }}>
                    {done ? "已统计" : "扫描中"}
                  </span>
                </div>
              ))}
              <div style={{ marginTop: 35, color: C.mint, fontSize: 32 }}>
                {done ? "扫描完成" : "正在读取文件信息…"}
              </div>
            </div>
          </div>
        </Chrome>
      </div>
      <Footer />
    </SceneFrame>
  );
};
const FileRows: React.FC<{ f: number; preserve?: boolean }> = ({
  f,
  preserve = false,
}) => {
  const all = f >= at("selectAll");
  const unchecked = f >= at("unselectBackup");
  return (
    <>
      {rows.map((r, i) => (
        <div
          key={r}
          style={{
            display: "flex",
            gap: 26,
            height: 140,
            padding: "18px 0",
            alignItems: "center",
            borderBottom: `1px solid ${C.white}22`,
            transform: `translateY(${breathe(f + i * 10) * 0.5}px)`,
          }}
        >
          <Check on={all && !(i === 2 && unchecked)} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 37, fontWeight: 550 }}>{r}</div>
            <div style={{ fontSize: 23, marginTop: 9, color: C.white }}>
              {paths[i]}
            </div>
          </div>
          {i === 2 && preserve && (
            <span style={{ fontSize: 30, color: C.mint }}>
              {unchecked ? "已取消勾选" : "个人数据"}
            </span>
          )}
        </div>
      ))}
    </>
  );
};
export const Select: React.FC<{ f: number }> = ({ f }) => {
  const clicked = f >= at("selectAll");
  const d = f - at("selectAll");
  return (
    <SceneFrame f={f} scene="select" style={shell()}>
      <Topline label="02 / 选择" />
      <Label y={160}>全选之后，仍由你决定。</Label>
      <div
        style={{
          position: "absolute",
          left: 300,
          top: 330,
          width: 1320,
          ...motion(f),
        }}
      >
        <Chrome title="清理 · 逐项审查">
          <div style={{ padding: "16px 44px 30px" }}>
            <FileRows f={f} />
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                marginTop: 28,
                alignItems: "center",
              }}
            >
              <div style={{ fontSize: 29 }}>
                {clicked ? "已选 3 项" : "未选择项目"}
              </div>
              <div style={{ display: "flex", gap: 20 }}>
                <Button active={clicked}>全选</Button>
                <Button active={false}>取消全选</Button>
              </div>
            </div>
          </div>
        </Chrome>
      </div>
      <Cursor
        x={1330 + (1 - ramp(f, at("selectAll") - 30)) * 100}
        y={902}
        down={d >= 0 && d < 10}
      />
      <Footer />
    </SceneFrame>
  );
};
export const Preserve: React.FC<{ f: number }> = ({ f }) => {
  const off = f >= at("unselectBackup");
  const cursorMove = ramp(f, at("unselectBackup") + 20, 25);
  const d = f - at("unselectBackup");
  return (
    <SceneFrame f={f} scene="preserve" style={shell()}>
      <Topline label="03 / 保留" />
      <Label y={160}>个人数据，自己决定。</Label>
      <div
        style={{
          position: "absolute",
          left: 300,
          top: 330,
          width: 1320,
          ...motion(f),
        }}
      >
        <Chrome title="清理 · 手动取消设备备份">
          <div style={{ padding: "16px 44px 30px" }}>
            <FileRows f={f} preserve />
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                marginTop: 28,
                alignItems: "center",
              }}
            >
              <div style={{ fontSize: 29, color: C.mint }}>
                {off ? "设备备份未选 · 保留" : "先检查，再选择"}
              </div>
              <div
                style={{
                  transform: `scale(${f >= at("reviewOpen") && f < at("reviewOpen") + 10 ? 0.96 : 1})`,
                }}
              >
                <Button>审查 {off ? "2" : "3"} 项</Button>
              </div>
            </div>
          </div>
        </Chrome>
      </div>
      <Cursor
        x={354 + cursorMove * 1096}
        y={752 + cursorMove * 150}
        down={
          (d >= 0 && d < 10) ||
          (f >= at("reviewOpen") && f < at("reviewOpen") + 10)
        }
      />
      <Footer />
    </SceneFrame>
  );
};
export const Review: React.FC<{ f: number }> = ({ f }) => {
  const selected = f >= at("quitOption");
  return (
    <SceneFrame f={f} scene="review" style={shell()}>
      <Topline label="04 / 确认" />
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 250,
          width: 530,
          ...motion(f),
        }}
      >
        <div style={{ fontSize: 82, lineHeight: 1.3, fontWeight: 650 }}>
          先退出，
          <br />
          再清理。
        </div>
        <div style={{ fontSize: 32, lineHeight: 1.7, marginTop: 38 }}>
          先保存工作。
          <br />
          正常退出，未退出则跳过。
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 710,
          top: 205,
          width: 1090,
          ...motion(f),
        }}
      >
        <Chrome title="最后确认一下">
          <div style={{ padding: "32px 40px" }}>
            <div style={{ fontSize: 37, fontWeight: 600 }}>
              普通缓存永久删除
            </div>
            <div style={{ fontSize: 28, marginTop: 16 }}>
              已选 2 项 · 设备备份未选
            </div>
            <div
              style={{
                marginTop: 35,
                borderTop: `1px solid ${C.white}33`,
                paddingTop: 28,
                fontSize: 29,
              }}
            >
              遇到运行中的应用
            </div>
            {["跳过运行中项目", "退出相关应用后清理"].map((x, i) => (
              <div
                key={x}
                style={{
                  marginTop: 18,
                  padding: "17px 20px",
                  borderRadius: 13,
                  border: `2px solid ${(i === 1 ? selected : !selected) ? C.mint : C.white + "55"}`,
                  display: "flex",
                  alignItems: "center",
                  gap: 20,
                  fontSize: 34,
                  background: i === 1 && selected ? C.ink : "transparent",
                }}
              >
                <div
                  style={{
                    width: 22,
                    height: 22,
                    border: `2px solid ${C.mint}`,
                    borderRadius: 20,
                    background: (i === 1 ? selected : !selected)
                      ? C.mint
                      : "transparent",
                  }}
                />
                {x}
              </div>
            ))}
            <div style={{ marginTop: 26, fontSize: 26, lineHeight: 1.6 }}>
              仅相关桌面应用与 Safari；其他运行中项目跳过
            </div>
            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                marginTop: 28,
              }}
            >
              <div
                style={{
                  transform: `scale(${f >= at("confirm") && f < at("confirm") + 10 ? 0.96 : 1})`,
                }}
              >
                <Button>确认处理 2 项</Button>
              </div>
            </div>
          </div>
        </Chrome>
      </div>
      <Cursor
        x={1330 + ramp(f, at("confirm") - 24, 24) * 200}
        y={690 + ramp(f, at("confirm") - 24, 24) * 175}
        down={
          (f >= at("quitOption") && f < at("quitOption") + 10) ||
          (f >= at("confirm") && f < at("confirm") + 10)
        }
      />
      <Footer />
    </SceneFrame>
  );
};
export const Result: React.FC<{ f: number }> = ({ f }) => {
  const done = f >= at("resultComplete");
  return (
    <SceneFrame f={f} scene="result" style={shell(false)}>
      <Topline label="05 / 结果" dark={false} />
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 220,
          fontSize: 85,
          fontWeight: 650,
          lineHeight: 1.3,
          ...motion(f),
        }}
      >
        处理与跳过，
        <br />
        都说清。
      </div>
      <div
        style={{
          position: "absolute",
          left: 890,
          top: 200,
          width: 900,
          ...motion(f),
        }}
      >
        <div style={{ fontSize: 35, fontWeight: 600, marginBottom: 40 }}>
          {done ? "示例结果" : "确认处理 2 项"}
        </div>
        {[
          ["浏览器缓存", "已处理"],
          ["设备备份", "未选 · 保留"],
          ["npm 下载缓存", "仍在运行 · 跳过"],
        ].map(([x, y], i) => (
          <div
            key={x}
            style={{
              borderTop: `1px solid ${C.ink}44`,
              padding: "32px 0",
              display: "flex",
              justifyContent: "space-between",
              fontSize: 34,
              transform: `translateY(${breathe(f + i * 8) * 0.5}px)`,
              opacity: 1,
            }}
          >
            <span>{x}</span>
            <span style={{ fontWeight: 650 }}>
              {done ? y : x === "设备备份" ? "未选 · 保留" : "等待处理"}
            </span>
          </div>
        ))}
        <div style={{ fontSize: 28, lineHeight: 1.65, marginTop: 24 }}>
          缓存可能重新生成。
          <br />
          示例流程已压缩等待时间。
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 125,
          top: 750,
          padding: "19px 28px",
          border: `1px solid ${C.ink}`,
          borderRadius: 16,
          fontSize: 32,
        }}
      >
        设备备份留在原位
      </div>
      <Footer dark={false} />
    </SceneFrame>
  );
};
export const Analyze: React.FC<{ f: number }> = ({ f }) => {
  const open = f >= at("openFolder");
  const d = f - at("openFolder");
  return (
    <SceneFrame f={f} scene="analyze" style={shell()}>
      <Topline label="06 / 分析" />
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 250,
          width: 500,
          ...motion(f),
        }}
      >
        <div style={{ fontSize: 82, fontWeight: 650, lineHeight: 1.35 }}>
          逐层看清
          <br />
          磁盘占用。
        </div>
        <div style={{ fontSize: 32, marginTop: 35 }}>
          点进文件夹，继续往里看。
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 710,
          top: 235,
          width: 1090,
          ...motion(f),
        }}
      >
        <Chrome title={open ? "分析 · ~/Projects" : "分析 · ~/"}>
          <div style={{ padding: 28 }}>
            <div style={{ fontSize: 28, marginBottom: 22 }}>
              {open ? "~/Projects" : "~/"}
            </div>
            <div
              style={{
                height: 475,
                display: "grid",
                gridTemplateColumns: open ? "1.25fr 1fr" : "1.7fr 1fr",
                gap: 12,
                transform: `scale(${1 + Math.sin(Math.max(0, d) / 20) * 0.003})`,
              }}
            >
              <div
                style={{
                  background: C.mint,
                  color: C.ink,
                  padding: 30,
                  borderRadius: 14,
                  display: "flex",
                  alignItems: "flex-end",
                  fontSize: 48,
                  fontWeight: 650,
                }}
              >
                {open ? "Web" : "Projects"}
              </div>
              <div
                style={{
                  display: "grid",
                  gridTemplateRows: "1fr 1.3fr",
                  gap: 12,
                }}
              >
                {(open ? ["Design", "Tools"] : ["Downloads", "Documents"]).map(
                  (x, i) => (
                    <div
                      key={x}
                      style={{
                        borderRadius: 14,
                        background: i === 0 ? C.teal : C.ink,
                        color: i === 0 ? C.ink : C.white,
                        padding: 25,
                        display: "flex",
                        alignItems: "flex-end",
                        fontSize: 32,
                        border: `1px solid ${C.white}33`,
                      }}
                    >
                      {x}
                    </div>
                  ),
                )}
              </div>
            </div>
          </div>
        </Chrome>
      </div>
      <Cursor x={1080} y={600} down={d >= 0 && d < 10} />
      <Footer />
    </SceneFrame>
  );
};
const Wave: React.FC<{ f: number; color?: string }> = ({
  f,
  color = C.mint,
}) => (
  <svg viewBox="0 0 600 110" style={{ width: "100%", height: 100 }}>
    <path
      d={Array.from(
        { length: 100 },
        (_, i) =>
          `${i === 0 ? "M" : "L"}${i * 6.07},${55 + Math.sin(i * 0.17 + f / 28) * 18 + Math.sin(i * 0.41 - f / 40) * 9}`,
      ).join(" ")}
      fill="none"
      stroke={color}
      strokeWidth="3"
    />
  </svg>
);
export const Status: React.FC<{ f: number }> = ({ f }) => (
  <SceneFrame f={f} scene="status" style={shell()}>
    <Topline label="07 / 状态" />
    <Label y={160}>系统心跳，一眼可见。</Label>
    <div
      style={{
        position: "absolute",
        left: 180,
        top: 345,
        width: 1560,
        display: "grid",
        gridTemplateColumns: "1fr 1fr",
        gap: 22,
      }}
    >
      {[
        ["CPU", "12%"],
        ["内存", "18.4 GB"],
        ["网络", `${(2.4 + Math.sin(f / 45) * 0.1).toFixed(1)} MB/s`],
        ["温度", "46°C"],
      ].map(([label, value], i) => (
        <div
          key={label}
          style={{
            padding: "25px 34px",
            borderRadius: 24,
            border: `1px solid ${C.white}44`,
            background: C.ink,
            transform: `translateY(${breathe(f + i * 14)}px)`,
          }}
        >
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              fontSize: 30,
            }}
          >
            <span>{label}</span>
            <span style={{ fontSize: 37, fontWeight: 600 }}>{value}</span>
          </div>
          <Wave f={f + i * 30} />
          {label === "温度" && (
            <span style={{ fontSize: 23 }}>依机型与系统支持</span>
          )}
        </div>
      ))}
    </div>
    <Footer />
  </SceneFrame>
);
export const Theme: React.FC<{ f: number }> = ({ f }) => {
  const light = f >= at("themeSwitch");
  return (
    <SceneFrame f={f} scene="theme" style={shell(light ? false : true)}>
      <Topline label="08 / 明暗主题" dark={!light} />
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 230,
          fontSize: 91,
          fontWeight: 650,
          lineHeight: 1.35,
          ...motion(f),
        }}
      >
        明暗之间，
        <br />
        依然清晰。
      </div>
      <div
        style={{
          position: "absolute",
          left: 950,
          top: 260,
          width: 800,
          ...motion(f),
        }}
      >
        <Chrome title="Clean · 外观" light={light}>
          <div style={{ padding: "45px 40px 40px" }}>
            <div style={{ fontSize: 44, fontWeight: 600, marginBottom: 40 }}>
              选择外观
            </div>
            <div style={{ display: "flex", gap: 18 }}>
              {["浅色", "深色", "跟随系统"].map((x, i) => (
                <div
                  key={x}
                  style={{
                    padding: "18px 23px",
                    borderRadius: 13,
                    border: `2px solid ${light ? C.ink : C.white}`,
                    background: (light ? i === 0 : i === 1)
                      ? C.mint
                      : "transparent",
                    color: (light ? i === 0 : i === 1)
                      ? C.ink
                      : light
                        ? C.ink
                        : C.white,
                    fontSize: 29,
                  }}
                >
                  {x}
                </div>
              ))}
            </div>
            <div style={{ marginTop: 44, fontSize: 32 }}>本机处理</div>
            <div style={{ marginTop: 12, fontSize: 29 }}>
              所有删除均需确认。
            </div>
          </div>
        </Chrome>
      </div>
      <Cursor
        x={1042 + ramp(f, at("themeSwitch") + 12, 24) * 95}
        y={473 + ramp(f, at("themeSwitch") + 12, 24) * 100}
        down={f >= at("themeSwitch") && f < at("themeSwitch") + 10}
      />
      <Footer dark={!light} />
    </SceneFrame>
  );
};
export const Signoff: React.FC<{ f: number }> = ({ f }) => (
  <SceneFrame f={f} scene="signoff" style={shell(false)}>
    <Topline label="原生 macOS 磁盘工具" dark={false} />
    <Img
      src={staticFile("clean-icon.png")}
      style={{
        position: "absolute",
        width: 235,
        height: 235,
        left: 842.5,
        top: 185,
        transform: `translateY(${breathe(f)}px)`,
      }}
    />
    <div
      style={{
        position: "absolute",
        top: 440,
        width: "100%",
        textAlign: "center",
        fontSize: 110,
        fontWeight: 650,
        ...motion(f),
      }}
    >
      Clean<span style={{ color: C.ink }}>.</span>
    </div>
    <div
      style={{
        position: "absolute",
        top: 610,
        width: "100%",
        textAlign: "center",
        fontSize: 54,
      }}
    >
      先看清，再动手。
    </div>
    <div
      style={{
        position: "absolute",
        top: 760,
        left: 590,
        width: 740,
        border: `1px solid ${C.ink}`,
        borderRadius: 50,
        padding: "23px 30px",
        fontSize: 34,
        textAlign: "center",
        transform: `translateY(${breathe(f + 30)}px)`,
      }}
    >
      bennix.github.io/Clean <span style={{ marginLeft: 20 }}>↗</span>
    </div>
    <Footer dark={false} />
  </SceneFrame>
);
export const SCENES = [
  Hook,
  Scan,
  Select,
  Preserve,
  Review,
  Result,
  Analyze,
  Status,
  Theme,
  Signoff,
];
export const Handoff: React.FC<{ f: number }> = ({ f }) => {
  const i = Math.min(
    9,
    T.scenes.findIndex((s) => f >= s.start && f < s.start + s.duration),
  );
  const local = f - T.scenes[i].start;
  if (i > 0 && local >= 24) return null;
  const size = i === 0 ? 520 : 520 + ease(local / 24) * 3980;
  return (
    <div
      style={{
        position: "absolute",
        left: A.x - size / 2,
        top: A.y - size / 2,
        width: size,
        height: size,
        border: `2px solid ${C.teal}`,
        borderRadius: "50%",
        opacity: i === 0 ? 0.65 : 0.7,
        pointerEvents: "none",
      }}
    />
  );
};
