# Chemical Collision（化学碰撞）Android 导出交接文档

> 交接时间：2026-11-02（同日追加：release 签名已配好，产物按 `debug\` / `release\` / `_obsolete\` 分类）
> 上一手已把「Godot 4.7.2 导出模板 + Android SDK + 导出预设 + 启动图标」全部配好，
> **现在 debug / release 两种包都能直接导出**。下面写清环境、改动、验证结果、待办和踩过的坑。

---

## 1. 一句话现状

**debug 与 release 两条出包链路都已跑通**（v2+v3 签名验证通过，`arm64-v8a`），产物按用途分类存放：

```
D:\Export_Godot_Pack\android_export\
├── debug\    chemical-pre1002-debug.apk      28,602,366 B   调试签名（自测 / 测试机）
├── release\  chemical-pre1002-release.apk    26,787,359 B   发布签名（分发 / 上架）
└── _obsolete\chemical-pre1002-unsigned-20261102-1929.apk     签名失败留下的未签名半成品（装不上）
```

**尚未在真机上跑过**，GL 兼容渲染与触屏适配（`ARCHITECTURE.md` §12 的 A1/B/C）的实际表现未验证。

---

## 2. 环境

| 项 | 值 |
|---|---|
| Godot 编辑器 | `D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（`4.7.2.stable.official.ed1daf0bf`，命令行用 console 版才有输出） |
| 工程目录 | `D:\Github_Library\Chemical\Chemical_Collision\chemical-1`（git 仓库，当前分支 `new`） |
| 导出模板 | `%APPDATA%\Godot\export_templates\4.7.2.stable\`（35 个文件 / 1.93 GB，`version.txt` = `4.7.2.stable`） |
| Android SDK | `C:\Users\clearrain\AppData\Local\Android\Sdk` |
| JDK | `C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot`（Godot 4.7 要求 17） |
| 调试签名 | `%APPDATA%\Godot\keystores\debug.keystore`，别名 `androiddebugkey`，密码 `android`，有效期到 2053 |
| 发布签名 | `D:\keys\chemical-release.keystore`，别名 `chemical`，有效期 10000 天（约 27 年）；密码存在 `D:\keys\chemical-release.credentials.txt`（**勿提交、勿丢**，丢了已安装用户无法更新） |

**SDK 已安装组件**：`cmdline-tools`（sdkmanager 19.0）、`platform-tools`（adb）、`build-tools;35.0.0` + `build-tools;36.0.0`、`platforms;android-35` + `platforms;android-36`，许可协议已全部接受。

编辑器设置里这几个键已经正确（不用再改）：
```
export/android/android_sdk_path = C:\Users\clearrain\AppData\Local/Android/Sdk
export/android/java_sdk_path    = C:/Program Files/Eclipse Adoptium/jdk-17.0.19.10-hotspot
export/android/debug_keystore   = C:/Users/clearrain/AppData/Roaming/Godot/keystores/debug.keystore
export/android/debug_keystore_pass = android
```

---

## 3. 首次配好环境那一轮的改动（历史记录）

> 后续轮次的改动见：触屏适配 A1/B/C → `ARCHITECTURE.md` §12；release 签名与双包分类 → 本文 §6.1 / §7.8 / §7.9。

```
chemical-1/export_presets.cfg | 16 行
chemical-1/project.godot      |  1 行
```

### `project.godot`（只加了 1 行，桌面端仍是 Forward+）
```ini
[rendering]

renderer/rendering_method.mobile="gl_compatibility"
rendering_device/driver.windows="d3d12"
textures/vram_compression/import_etc2_astc=true
```
原因：原来移动端继承 Forward+，需要 Vulkan，老机型没有 Vulkan 驱动会黑屏。卡牌 2D 项目用 GL 兼容更稳。

### `export_presets.cfg`（Android 预设 = preset.1）

| 键 | 值 |
|---|---|
| `export_path` | `../../../../Export_Godot_Pack/Chemical Collision——pre1002.apk` |
| `package/unique_name` | `com.clearrain.chemicalcollision` |
| `package/name` | `化学碰撞` |
| `version/name` | `1.0.0` |
| `version/code` | `1` |
| `launcher_icons/main_192x192` | `res://export_icons/icon_192.png` |
| `launcher_icons/adaptive_foreground_432x432` | `res://export_icons/adaptive_fg_432.png` |
| `launcher_icons/adaptive_background_432x432` | `res://export_icons/adaptive_bg_432.png` |
| `architectures/arm64-v8a` | `true`（其余三项 false） |
| `gradle_build/use_gradle_build` | `false`（用预编译模板，不需要 `android/build`） |

### 新增资源 `res://export_icons/`
由 `res://chemical1-test.png`（64×64，也就是原 Win 版 exe 的图标，`uid://cjwf6wpblp4f0`）生成的：
- `icon_192.png` — 192×192 传统启动图标（最近邻放大，保留像素风）
- `adaptive_fg_432.png` — 432×432 透明前景，内容缩到 256px 居中
- `adaptive_bg_432.png` — 432×432 纯底色 `#ECE4D1`（取自原图左上角）
- `icon_512.png` — 512×512，Google Play 商店用，**未接进预设**

⚠️ 源图只有 64×64，放大到 432 会有明显颗粒。拿到 512×512 以上的原图后，**直接覆盖这三个文件即可，配置不用动**。

---

## 4. 已验证的结果（2026-11-02 复验，两个包都是 CLI 无头导出后实测）

| 项 | debug 包 | release 包 |
|---|---|---|
| 路径 | `D:\Export_Godot_Pack\android_export\debug\chemical-pre1002-debug.apk` | `D:\Export_Godot_Pack\android_export\release\chemical-pre1002-release.apk` |
| 大小 | 28,602,366 B（27.3 MB） | 26,787,359 B（25.5 MB） |
| 签名 | v2 ✅ v3 ✅（`CN=Godot, OU=Godot Engine, O=Stichting Godot, C=NL`） | v2 ✅ v3 ✅（`CN=Chemical Collision, O=ClearRain, C=CN`） |
| 包名 / 版本 | `com.clearrain.chemicalcollision` / `versionCode 1` / `1.0.0` | 同左 |
| 应用名 | `化学碰撞` | 同左 |
| SDK | `minSdk 24` / `targetSdk 36` / `compileSdk 36` | 同左 |
| native-code | `arm64-v8a` | 同左 |
| 权限 | `android.permission.VIBRATE` ✅（选牌震动依赖它） | 同左 |

导出日志里的三个关键行：`Adding permission android.permission.VIBRATE` → `正在签名调试/发布 APK……` → `Signed` → `[ DONE ] export`。

APK 内部 `assets/` 已包含 `project.binary`、`*.gdc`、`backend/*.ctex`、`assets.sparsepck`——**手机只要传这一个 APK**，不像 Windows 要 exe + pck。

---

## 5. 待办（按优先级）

1. **真机验证**（最高优先级，唯一没验证的环节）
   装 APK 后看是否正常进主菜单、卡牌渲染/触摸是否正常、有无黑屏或闪退。
   ```powershell
   adb devices
   adb install -r chemical-debug.apk
   adb logcat -s godot:V   # 抓引擎日志
   ```
   如果黑屏 → 说明 GL 兼容也有问题，改回 `renderer/rendering_method.mobile="mobile"` 或用 Vulkan 试。

2. ~~**release keystore**~~ ✅ **已完成（2026-11-02）**
   `D:\keys\chemical-release.keystore`（别名 `chemical`，RSA 2048，10000 天）已生成，
   并写进 `.godot/export_credentials.cfg` 的 `keystore/release*` 三项（该文件在 `.gitignore` 里）。
   密码存在 `D:\keys\chemical-release.credentials.txt`——**这两个文件务必备份，丢了就无法给已安装用户发更新**。
   重新生成（慎用，会让已发布包无法升级）：
   ```powershell
   & "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\bin\keytool.exe" -genkeypair -v `
     -keystore D:\keys\chemical-release.keystore -alias chemical -keyalg RSA -keysize 2048 -validity 10000
   ```

3. **模拟器测试**：预设只勾了 `arm64-v8a`，x86_64 模拟器装不上。要测模拟器就勾 `architectures/x86_64`（APK 会大 70 MB 左右）。

4. **局域网联机**：`scripts/net/` 目前只有 `LoopbackTransport`（进程内回环），没有 ENet 实现。等接 ENet 时，必须同时在预设里勾 **`permissions/internet`** 并重新导出，否则 Android 上网络请求会被系统拒绝。

5. **可选**：`application-label` 现在是「化学碰撞」，包名是 `com.clearrain.chemicalcollision`——这两个是可随时改的，但要趁没上架前定下来。

---

## 6. 出包分类与常用命令

### 6.1 产物分类（一律按签名类型分目录，不要混放）

```
D:\Export_Godot_Pack\android_export\
├── debug\
│   └── chemical-pre1002-debug.apk      28.6 MB   debug 签名
├── release\
│   └── chemical-pre1002-release.apk    26.8 MB   release 签名
└── _obsolete\
    └── chemical-pre1002-unsigned-20261102-1929.apk   未签名半成品（装不上，确认后可删）
```

| 目录 | 签名 | 用途 | 备注 |
|---|---|---|---|
| `debug\` | `androiddebugkey`（`%APPDATA%\Godot\keystores\debug.keystore`） | 自测、给测试机装、看日志 | 可 `adb install -r` 直接覆盖同签名旧包 |
| `release\` | `chemical`（`D:\keys\chemical-release.keystore`） | 分发、上架 | **与 debug 包签名不同，装前必须先卸载 debug 包** |

`.idsig` 是 apksigner v4 增量签名的副产物，**只在 `adb install --incremental` 时用**，拷手机不需要它。

**谁读哪把钥匙（这次报错的根源）：**

| 导出方式 | 密钥库来源 | 缺了报什么 |
|---|---|---|
| `--export-debug` / 勾「调试导出」 | 编辑器设置 `export/android/debug_keystore` | 找不到调试密钥库 |
| `--export-release` / 直接点「导出项目」 | 预设 → `.godot/export_credentials.cfg` 的 `keystore/release` | **找不到发布密钥库** |

两把钥匙**互不通用**：release 导出不会退回用 debug 密钥库。

### 6.2 命令

```powershell
$godot = "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\Github_Library\Chemical\Chemical_Collision\chemical-1"
$sdk   = "C:\Users\clearrain\AppData\Local\Android\Sdk"
$out   = "D:\Export_Godot_Pack\android_export"

# 调试包（走编辑器设置里的 debug keystore）
& $godot --headless --path $proj --export-debug   "Android" "$out\debug\chemical-pre1002-debug.apk"

# 发布包（走 .godot/export_credentials.cfg 里的 keystore/release）
& $godot --headless --path $proj --export-release "Android" "$out\release\chemical-pre1002-release.apk"

# 导出 Windows（预设名是 "Chemical Collision"）
& $godot --headless --path $proj --export-release "Chemical Collision" "D:\out\game.exe"

# 验签 + 看包信息（四个关键值：v2/v3、包名、versionCode、VIBRATE）
& "$sdk\build-tools\36.0.0\apksigner.bat" verify --verbose "$out\release\chemical-pre1002-release.apk"
& "$sdk\build-tools\36.0.0\aapt2.exe" dump badging "$out\release\chemical-pre1002-release.apk"

# 装到手机（debug 与 release 签名不同，跨类型要先 uninstall）
& "$sdk\platform-tools\adb.exe" install -r "$out\debug\chemical-pre1002-debug.apk"
```

`apksigner.bat` 需要 `java` 在 PATH 上，否则报 `java` 找不到：
```powershell
$env:PATH = "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\bin;$env:PATH"
```

无头导出时**不要用管道提前掐断输出**（例如 `| Select-Object -First 10`），PowerShell 会关掉管道把 Godot 进程杀掉，导出会半途失败（这次踩过，现象是 APK 没生成但没有任何 ERROR）。

---

## 7. 踩过的坑（务必看，能省你一小时）

### 7.1 千万别用 PowerShell 的 `Get-Content`/`Set-Content` 改这两个 cfg 文件
`export_presets.cfg` 里有中文和 `——`，`project.godot` 被写成了 **UTF-8 带 BOM**（Godot 会报无法解析）。
PS 默认按 ANSI 读，会把 `——` 变成 `鈥斺€`，写回去还能带 BOM。

正确做法：用 Python 按字节/UTF-8 处理：
```python
import io
p = r'D:\Github_Library\Chemical\Chemical_Collision\chemical-1\export_presets.cfg'
s = io.open(p, encoding='utf-8').read()
s = s.replace('旧值', '新值')
io.open(p, 'w', encoding='utf-8', newline='').write(s)
```
或者直接用编辑器 UI 改。**改完用 `git diff` 确认 `——`、`化学碰撞` 显示正常、没有 BOM。**

### 7.2 模板必须放在「编辑器版本号同名」的目录
`4.7.2` 的编辑器只认 `export_templates\4.7.2.stable\`。
同事原来那里放的是从 `4.7.stable` 拷来的 Windows 模板（`windows_debug_x86_64.exe` 大小 103,055,872 与 4.7 包完全一致，且缺 `windows_release_arm64.exe`）。
这次换成了官方 4.7.2 全量包（`windows_debug_x86_64.exe` 应为 103,176,704）。
**副作用：建议重新导一次 Windows 版确认没问题。**

### 7.3 下载源
本机 `hosts` 把 `github.com`、`api.github.com`、`objects.githubusercontent.com`、`raw.githubusercontent.com` 等全部指向 `127.0.0.1`（拉黑）。

- 走镜像可用：`https://ghproxy.net/https://github.com/<owner>/<repo>/releases/download/<tag>/<file>`
- 其他镜像实测：`gh-proxy.com` 慢（0.15 MB/s）、`ghfast.top` / `ghproxy.cc` / `github.moeyy.xyz` / `hub.gitmirror.com` 全部不通
- 本机带宽上限约 **0.9 MB/s**，**并行分段无收益**（实测 4 路合计 0.71 MB/s），老老实实单线程 + `curl -C -` 断点续传
- `dl.google.com` 直连正常（同样 ~0.9 MB/s）

### 7.4 build-tools 要和 targetSdk 对齐
模板的 `targetSdkVersion` 是 **36**。只装 `build-tools;35.0.0` 时导出会警告
`Could not find version of build tools that matches Target SDK, using 35.0.0`。
已补装 `build-tools;36.0.0` + `platforms;android-36`，警告消除。

### 7.5 Windows 预设的 `export_path` 曾被改成 `…pre1002_test.exe` —— **已还原**
做手机适配那轮做 Windows 冒烟导出时把 `pre1002.exe` 改成了 `pre1002_test.exe`（避免覆盖正式包），
**本轮已还原为 `../../../../Export_Godot_Pack/Chemical Collision——pre1002.exe`**，`git diff` 里这一行不再出现，
`export_presets.cfg` 的其余改动（Android 路径 / 包名 / 图标 / `permissions/vibrate`）都是本轮要保留的。

### 7.6 无头导出会写工程缓存
`--headless` 导出会更新工程的 `.godot/` 目录（`imported/`、`exported/`、`uid_cache.bin` 等），这是正常的，`.godot/` 已在 `.gitignore` 里。

### 7.7 后续如果用 gradle 构建
现在 `gradle_build/use_gradle_build=false`，不需要 `android/build`。
一旦改成 `true`（要改 AndroidManifest、加安卓插件、改应用名图标运行时），必须先在编辑器「项目 → 安装 Android 构建模板」，生成 `res://android/build`。
注意工程 `.gitignore` 里有 `/android/`，**构建模板不会被提交**，换机器要重新装一次。

### 7.8 「[代码签名] 找不到发布密钥库，无法导出」

**含义**：内容已经打进 APK，走到最后一步签名时找不到**发布**密钥库，导出中止。

**根因排查顺序**（本机 2026-11-02 实测）：

1. `.godot/export_credentials.cfg` 里 `keystore/release=""`（预设「高级选项 → 密钥库 → 发布」没填）→ **这就是本次的原因**；
2. 调试导出走的是编辑器设置 `export/android/debug_keystore`，**不是**预设里的 `keystore/debug`，两处都空也不影响 debug 包；
3. release 导出**不会**退回用 debug 密钥库，必须显式提供发布密钥库。

**修**：按 §6.2 的 `--export-release`（已配好 `D:\keys\chemical-release.keystore`），
或者只想快速出可安装的包 → 改用 `--export-debug` / 在导出面板勾「调试导出」。

顺带一条：`D:\Export_Godot_Pack\android_export\_obsolete\chemical-pre1002-unsigned-20261102-1929.apk`
（26,920,798 B）是这次签名失败留下的**未签名半成品**，装不上 —— 已从根目录挪进 `_obsolete\` 分类，确认无用即可删。

### 7.9 导出预设被编辑器写回默认值（包名 / 图标 / 震动权限全丢）

**症状**：`git status` 里 `export_presets.cfg` 突然有改动，内容是新建预设的默认值：

| 键 | 正常值 | 被写回 |
|---|---|---|
| `package/unique_name` | `com.clearrain.chemicalcollision` | `com.example.$genname` |
| `package/name` | `化学碰撞` | 空 |
| `version/name` | `1.0.0` | 空 |
| `launcher_icons/*` | `res://export_icons/*.png` | 全空 |
| `permissions/vibrate` | `true` | `false` |
| `export_path`（Windows） | `…pre1002.exe` | `…pre1002_test.exe` |

**影响**：不改回来直接导出，会得到「随机包名 + 无图标 + 没有振动权限」的包，触屏适配里的选牌震动会静默失效。

**处理**：**先关掉 Godot 编辑器**（开着时它内存里还是那份默认值，你一保存导出就再覆盖一遍），然后
```
git checkout -- chemical-1/export_presets.cfg
```
再核对下面四项是否回来了：`package/unique_name` / `package/name` / `version/name` / `permissions/vibrate`。
改完导出的包用 `aapt2 dump badging` 复核（`application-label` 应为「化学碰撞」，权限里应有 `VIBRATE`）。

---

## 8. 备份与回滚

改动前的原文件已备份在：
```
C:\Users\clearrain\Documents\deepseek-harness\default-workspace\work-backup\export_presets.cfg.bak
C:\Users\clearrain\Documents\deepseek-harness\default-workspace\work-backup\project.godot.bak
```

回滚：
```powershell
Copy-Item "...\work-backup\export_presets.cfg.bak" "D:\Github_Library\Chemical\Chemical_Collision\chemical-1\export_presets.cfg" -Force
Copy-Item "...\work-backup\project.godot.bak"      "D:\Github_Library\Chemical\Chemical_Collision\chemical-1\project.godot" -Force
```

也可以直接 `git checkout -- project.godot export_presets.cfg`（会一起丢掉 Android 相关改动）。

模板安装包 `Godot_v4.7.2-stable_export_templates.tpz`（1.22 GB）还留在
`C:\Users\clearrain\Documents\deepseek-harness\default-workspace\tpl-dl\`，确认没问题后可删。
`%APPDATA%\Godot\export_templates\4.7.stable\`（旧的 4.7 模板，1.2 GB，连 `version.txt` 都没有）也已无用，可删。

---

## 9. 一页速查

| 问题 | 答案 |
|---|---|
| 手机要传几个文件？ | **1 个** APK。`.idsig` 只在 `adb install --incremental` 时用 |
| APK 在哪？ | 见 §6.1 分类目录：`D:\Export_Godot_Pack\android_export\debug\` 与 `…\release\` |
| 走哪种签名？ | 自测/测试机 → `debug\`；分发/上架 → `release\`。**两者签名不同，不能互相覆盖安装** |
| 为什么有两条渲染路径？ | 桌面 Forward+，移动端 GL 兼容（`rendering_method.mobile`） |
| 上架还缺什么？ | 512×512 高清图标 + 定稿包名/应用名（release keystore ✅ 已就绪） |
| 现在能装吗？ | 能，两个包都通过 v2+v3 验签；debug 包需允许「未知来源」 |
| 导出报「找不到发布密钥库」？ | 见 §7.8：用 `--export-release` 前必须配 `keystore/release`；只想快出包就 `--export-debug` |
| 包名突然变 `com.example.*`、图标没了？ | 见 §7.9：预设被编辑器写回默认值，关编辑器后 `git checkout -- export_presets.cfg` |
| 换机器要重装什么？ | 4.7.2 导出模板 + Android SDK + JDK 17，然后在编辑器设置里指路径；`D:\keys\` 里的发布密钥库要单独拷过去 |
