# PromptPanel Mobile (Android 伴侣端)

`PromptPanel Mobile` 是 `PromptPanel`（项目快贴）的 Android 手机端伴侣应用，与 macOS 原生客户端共享同一套数据结构与 `CloudSyncEnvelope (v2)` 云端同步协议。

## 核心场景设计（针对手机操作习惯优化）
1. **Tab 1：速记与待办（Inbox & Todos）**
   - 打开即用的随手记入口，支持随时记录手机端的待办事项、长文案临时草稿。
   - 支持一键勾选完成（划掉待办）或同步到 macOS 端直接粘贴执行。
2. **Tab 2：常用类型词库（Categories）**
   - 按「开发类」、「视频制作类」、「通用项目」等长期常驻类型浏览高频提示词，点按右侧按钮即可一键复制到手机剪贴板。
3. **Tab 3：项目管理（Projects）**
   - 按具体项目查看专属提示词，支持筛选/隐藏已归档项目，并展示完整创建时间、使用次数与版本号。
4. **冲突零丢失的 HTTPS 双向同步**
   - 与 macOS 端 `CloudSyncService` 使用完全一致的 JSON / AES-256-GCM+Gzip 同步信封格式（包含 `projects`、`entries`、`versions`），远程同步强制要求 `https://`（仅本机调试允许回环地址）。
   - 当手机端与 macOS 端并发修改同一条内容时，旧版本会自动转存进 `versions` 历史记录中，绝不丢失任何文字。

## 构建 Android 安装包（APK）

在已安装 Android SDK（`platforms/android-34`、`build-tools/34.0.0`）与 JDK 的机器上，可直接运行：

```bash
./mobile/build-android.sh
```

构建脚本会编译 `mobile/android/` 原生宿主与离线前端资产并执行 4 字节对齐（`zipalign`）。正式发版可通过环境变量注入 `ANDROID_KEYSTORE_PATH` 与 `ANDROID_KEY_PASS` 完成 **V1 (JAR) + V2 + V3** 签名与 `apksigner verify` 校验；未提供发行密钥时，脚本会在临时目录生成一次性开发校验密钥并在退出时自动销毁，产物默认输出至 `dist/release/PromptPanel-1.8.0+18-android.apk`。
