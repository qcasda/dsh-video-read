---
name: video-read
description: 用无头浏览器读取任意视频页面（抖音/B站/YouTube等）的画面字幕，输出紧凑时间轴。当用户发来视频链接或要求"看看这个视频讲了什么"时使用。全程后台运行，不占用用户屏幕。
whenToUse: 用户给出视频链接（抖音短链、B站、YouTube 等）并要求总结/理解视频内容时；或需要判断视频里出现了哪些文字、步骤、界面时。
---

# 视频读取（无头浏览器 + 帧 OCR）

## 一条命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\deepseek project\tools\video-read.ps1" -Url "<视频页地址>" -Frames 20
```

输出形如：

```
SRC: https://...
FRAMES: 20
f03 | 我的人生被 Claude 操控了 | My life is controlled by Claude
f07 | 这是我 3D 打印机 | This is my 3D printer
END lines=24
```

每行只给"这一帧新出现的字幕"，重复行已去重，token 很省。

## 工作原理

1. 启动 `msedge --headless=new --remote-debugging-port=9222 --user-data-dir=D:\工具\VideoKit\edgeprof`
   - **必须自定义 user-data-dir**：Edge 禁止在默认配置上开调试端口
2. `tools/page-frames.js` 通过 CDP 连接页面：移除登录遮罩 → 设 1600x900@2x 视口 → 4 倍速播放 → 定时 `Page.captureScreenshot` 截图（只截视频元素区域）
3. `tools/video-read.ps1` 对每帧裁出下方 45% 字幕区 → Windows OCR → 去重输出
4. 结束自动关闭无头浏览器

## 已知坑

| 现象 | 原因 / 处理 |
|---|---|
| 帧图都是同一个大小且内容相同 | 视频是 blob 流，`currentTime` seek 无效 → 必须**播放着截**（脚本已是 4x 播放） |
| 画面全是"扫码登录" | 抖音等站点弹登录遮罩 → 脚本已用 JS 移除 `position:fixed + z-index>10 + 含"登录"` 的层 |
| 字幕识别乱码 | 视口太小 → 调大 `Emulation.setDeviceMetricsOverride`（page-frames.js 内），或加 `-Frames` 提高密度 |
| 只有语音没有字幕 | 本流程读不到 → 需要 ASR（whisper.cpp + 模型，约 200MB），再走音频转写 |
| yt-dlp 下载失败（Fresh cookies needed） | 抖音需要 JS 签名 Cookie，`--cookies-from-browser` 被 App-Bound 加密挡住 → 不要走 yt-dlp 路线 |

## 语音转写（有语音、无字幕时用）

faster-whisper 已装（small 模型已缓存），流程：

```powershell
# 1. 用 page-media.js 抓到 audio 流地址（写进 media.json）
node tools\page-media.js 9222 10 D:\工具\VideoKit\media.json
# 2. 下载该 audio 地址后转 16k 单声道 wav
ffmpeg -y -i audio.m4a -ar 16000 -ac 1 -c:a pcm_s16le audio16k.wav
# 3. 转写（输出必须重定向到文件，否则控制台是乱码）
$env:PYTHONIOENCODING="utf-8"; python tools\transcribe.py audio16k.wav small | Out-File transcript.txt -Encoding utf8
```

注意：`faster-whisper` 内置的 av 解码在本机会报 `metadata_errors` 不兼容，所以脚本改成**直接读 wav 波形**传入，不要传 m4a。

## 相关文件

- `tools/video-read.ps1` — 一键入口
- `tools/page-frames.js` — CDP 抓帧
- `tools/ocr-words.ps1` — Windows OCR（返回带坐标的 JSON）
- `tools/get-cookies.js` — 需要 Cookie 时从无头浏览器导出 Netscape cookies.txt
- `D:\工具\VideoKit\` — Edge 临时配置、帧输出、yt-dlp/ffmpeg

## 成本提示

一次读取约 1–2 次工具调用，输出 20 行左右；比"抓屏 + 人工对齐"省一个数量级。视频越长，`-Frames` 越大，成本线性上升。
