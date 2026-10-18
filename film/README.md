# Clean 产品短片

30秒 / 1920×1080 / 60fps / 简体中文 / 原创代码合成音乐与音效。

产品事实固定于Clean1.1.1（ea370a1）。画面是React/SVG独立组件重建，不是截图平移；真实AppIcon原样使用。数字、路径样本和压缩操作节奏始终标注为演示。没有真实文件删除、释放容量、评分、价格或用户评价等虚构效果。

## 复现

Node 22+、Python3（numpy）、ffmpeg、ffprobe；字体已本地固定，OFL许可随附。

```sh
npm ci
./scripts/build.sh
python3 scripts/qa.py
```

所有时序在 `production/timing.json`，声音由 `scripts/audio.py` 固定种子合成；`src/scenes.tsx` 各镜独立，位置来自帧数。`public/audio/` 为可再生文件，不提交；源码和字体无API密钥。MP4和纯音乐在 `../docs/assets/`。

## 交付资料

- `production/brief.md`、`facts.json`、`storyboard.md`、`style-guide.md`、`research.md`
- `production/timing.json`、`ledger.md`、`quality.json`、独立评审报告
- `production/style-*.png` 三张风格帧，`contact-sheet.jpg` 15帧拼版
- `production/silent-contact-sheet.jpg` 静音2fps拼版
- `production/handoff.md` 人工确认边界与文件说明

网页播放器使用原生controls、playsinline、poster、preload=none，无自动播放；提供中文说明轨道和文字版。移动设备不裁切视频，细节建议横屏全屏观看。
