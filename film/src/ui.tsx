import React from "react";
import { C } from "./design";
export const Check: React.FC<{ on?: boolean; size?: number }> = ({
  on = false,
  size = 36,
}) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: 9,
      border: `2px solid ${on ? C.mint : C.white}`,
      background: on ? C.mint : "transparent",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      flexShrink: 0,
    }}
  >
    {on && (
      <svg width={size * 0.7} height={size * 0.7} viewBox="0 0 24 24">
        <path d="m4 12 5 5 11-11" fill="none" stroke={C.ink} strokeWidth="3" />
      </svg>
    )}
  </div>
);
export const Cursor: React.FC<{ x: number; y: number; down?: boolean }> = ({
  x,
  y,
  down = false,
}) => (
  <svg
    style={{
      position: "absolute",
      left: x,
      top: y,
      filter: "drop-shadow(0 3px 5px #0007)",
      transform: `scale(${down ? 0.86 : 1})`,
      transformOrigin: "top left",
    }}
    width="46"
    height="54"
    viewBox="0 0 30 36"
  >
    <path
      d="M3 2v29l8-8 5 11 5-2-5-10h12Z"
      fill={C.white}
      stroke={C.dark}
      strokeWidth="2"
    />
  </svg>
);
export const Button: React.FC<
  React.PropsWithChildren<{ active?: boolean; width?: number }>
> = ({ children, active = true, width }) => (
  <div
    style={{
      padding: "19px 28px",
      background: active ? C.mint : "transparent",
      border: `1px solid ${active ? C.mint : C.white}`,
      borderRadius: 14,
      color: active ? C.ink : C.white,
      fontSize: 34,
      fontWeight: 600,
      textAlign: "center",
      width,
      whiteSpace: "nowrap",
    }}
  >
    {children}
  </div>
);
export const Topline: React.FC<{ label: string; dark?: boolean }> = ({
  label,
  dark = true,
}) => (
  <div
    style={{
      position: "absolute",
      left: 120,
      top: 74,
      right: 120,
      display: "flex",
      justifyContent: "space-between",
      alignItems: "center",
      color: dark ? C.white : C.ink,
      fontSize: 27,
    }}
  >
    <span style={{ fontWeight: 650 }}>
      Clean<span style={{ color: dark ? C.mint : C.ink }}> .</span>
    </span>
    <span style={{ letterSpacing: 2, fontSize: 23 }}>{label}</span>
  </div>
);
export const Chrome: React.FC<
  React.PropsWithChildren<{ title: string; light?: boolean }>
> = ({ children, title, light = false }) => (
  <div
    style={{
      borderRadius: 27,
      overflow: "hidden",
      background: light ? C.white : C.dark,
      border: `1px solid ${light ? C.ink + "33" : C.white + "33"}`,
      boxShadow: "0 35px 85px #0003",
      color: light ? C.ink : C.white,
    }}
  >
    <div
      style={{
        height: 64,
        display: "flex",
        alignItems: "center",
        gap: 10,
        borderBottom: `1px solid ${light ? C.ink + "22" : C.white + "22"}`,
        padding: "0 25px",
        fontSize: 23,
      }}
    >
      {[0, 1, 2].map((x) => (
        <span
          key={x}
          style={{
            width: 12,
            height: 12,
            borderRadius: 10,
            background: light ? C.ink : C.mint,
            opacity: 0.35,
          }}
        />
      ))}
      <span style={{ marginLeft: 22 }}>{title}</span>
    </div>
    {children}
  </div>
);
export const Label: React.FC<
  React.PropsWithChildren<{ x?: number; y?: number; dark?: boolean }>
> = ({ children, x = 120, y = 200, dark = true }) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: y,
      color: dark ? C.white : C.ink,
      fontSize: 84,
      fontWeight: 650,
      lineHeight: 1.3,
    }}
  >
    {children}
  </div>
);
export const Footer: React.FC<{ dark?: boolean }> = ({ dark = true }) => (
  <div
    style={{
      position: "absolute",
      left: 120,
      right: 120,
      bottom: 52,
      display: "flex",
      justifyContent: "space-between",
      color: dark ? C.white : C.ink,
      fontSize: 24,
    }}
  >
    <span>界面重建 · 示例数据 · 演示节奏</span>
    <span>本机处理</span>
  </div>
);
