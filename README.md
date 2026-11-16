# dsh-video-read

**给文本模型装上"看视频"的能力：一条命令把任意网页视频读成时间轴文字，全程后台运行、不占用屏幕、单次成本约 ¥0.05。**

> Read any `<video>` web page into a timestamped text timeline — headless, no screen hijacking, ~$0.01 per video.

---

## 它解决什么问题

AI 编程助手/文本模型能读网页文字，但**看不了视频**。常见做法是：

- ❌ 人肉截图 → 太慢
- ❌ 抓屏 + 人眼对齐 → 占用屏幕，还容易读到别的窗口
- ❌ 直接调第三方视频 API → 要 key、要登录、要钱

这个工具的做法是：**无头浏览器渲染页面 → 跳帧截图 → OCR 字幕 → 只输出"新出现的文字"**。屏幕一秒都不会被占用。

## 效果

```
SRC: https://example.com/video/123
FRAMES: 20
f03 | 我的人生被 Claude 操控了 | My life is controlled by Claude
f07 | 这是我 3D 打印机 | This is my 3D printer
f12 | 他建议我买一个回音壁 | He suggested I buy a soundbar
END lines=40
```

20 帧对应 20 行以内，**比把 OCR 全文喂给模型省一个数量级的 token**。

## 依赖

| 依赖 | 说明 |
|---|---|
| Windows 10/11 | OCR 用的是系统自带的 `Windows.Media.Ocr`，**仅 Windows** |
| Microsoft Edge | 用它的 headless 模式渲染页面 |
| Node.js 18+ | 驱动 DevTools Protocol |
| ffmpeg（可选） | 只在 `-Audio` 语音转写时需要 |
| faster-whisper（可选） | `pip install faster-whisper`，`-Audio` 时需要 |

## 用法

```powershell
# 只读画面字幕
powershell -NoProfile -ExecutionPolicy Bypass -File tools\video-read.ps1 `
    -Url "https://www.douyin.com/video/xxxx" -Frames 20

# 同时做语音转写（需要 ffmpeg + faster-whisper）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\video-read.ps1 `
    -Url "https://www.bilibili.com/video/xxxx" -Frames 20 -Audio
```

参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Url` | 必填 | 视频页面地址（不是直链） |
| `-Frames` | 16 | 截多少帧；越长越密，成本线性上升 |
| `-Audio` | 关 | 是否抓音轨并转写 |
| `-WorkDir` | `%TEMP%\video-read` | 中间文件目录 |

## 作为 DSH 技能使用

把本仓库放进 `%USERPROFILE%\.dsh\skills\`（或项目的 `.dsh\skills\`），DSH 会自动加载 `SKILL.md`，之后直接说"读这个视频链接"即可。

## 工作原理

1. `msedge --headless=new --remote-debugging-port=9222 --user-data-dir=<temp>` 起一个隔离的无头实例
   - 必须自定义 user-data-dir：Edge 禁止在默认配置上开调试端口
2. `page-frames.js` 通过 CDP 连接页面：移除登录遮罩 → 设 1600×900@2x 视口 → 4 倍速播放 → 定时截图视频元素
3. `video-read.ps1` 裁出下方 45% 字幕区 → Windows OCR → 去重输出
4. `-Audio` 时再由 `page-media.js` 抓出音轨地址 → ffmpeg 转 16k wav → faster-whisper 转写

## 已知限制（重要）

| 限制 | 说明 |
|---|---|
| **只有 Windows** | OCR 依赖 WinRT，Linux/macOS 需要换成 tesseract/paddleocr |
| **只能读"画面上有的字"** | 无字幕的纯口播需要 `-Audio` |
| **OCR 准确率约 70%** | 中文字幕在 1000px 宽下易糊；英文更准；调大视口可改善 |
| **blob 流不能 seek** | 所以是"边播边截"，不是精确定位 |
| **登录墙** | 部分站点会弹登录；脚本只移除视觉遮罩，不做任何登录操作 |
| **动态站点会变** | 页面改版可能导致抓不到元素 |

## 免责声明

本工具仅用于**个人学习、无障碍阅读、内容研究**等正当用途。

- 请遵守目标网站的服务条款与 robots 协议
- 不得用于绕过付费墙、会员限制或批量抓取受版权保护的内容
- 使用者自行承担合规责任

## License

MIT
