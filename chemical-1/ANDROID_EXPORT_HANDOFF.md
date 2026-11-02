# Chemical Collision（化学碰撞）Android 导出交接文档

> 交接时间：2026-11-02
> 上一手已把「Godot 4.7.2 导出模板 + Android SDK + 导出预设 + 启动图标」全部配好，
> **现在可以直接导出可安装的 APK**。下面写清环境、改动、验证结果、待办和踩过的坑。

---

## 1. 一句话现状

Godot 编辑器里「项目 → 导出 → Android」已经能出包，产出的是**已签名的 debug APK**（27.3 MB，arm64-v8a）。
**尚未在真机上跑过**，GL 兼容渲染的实际表现未验证。

---

## 2. 环境

| 项 | 值 |
|---|---|
| Godot 编辑器 | `C:\Users\clearrain\Desktop\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe`（`4.7.2.stable.official.ed1daf0bf`） |
| 工程目录 | `D:\Github_Library\Chemical\Chemical_Collision\chemical-1`（git 仓库，当前分支 `new`） |
| 导出模板 | `%APPDATA%\Godot\export_templates\4.7.2.stable\`（35 个文件 / 1.93 GB，`version.txt` = `4.7.2.stable`） |
| Android SDK | `C:\Users\clearrain\AppData\Local\Android\Sdk` |
| JDK | `C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot`（Godot 4.7 要求 17） |
| 调试签名 | `%APPDATA%\Godot\keystores\debug.keystore`，别名 `androiddebugkey`，密码 `android`，有效期到 2053 |

**SDK 已安装组件**：`cmdline-tools`（sdkmanager 19.0）、`platform-tools`（adb）、`build-tools;35.0.0` + `build-tools;36.0.0`、`platforms;android-35` + `platforms;android-36`，许可协议已全部接受。

编辑器设置里这几个键已经正确（不用再改）：
```
export/android/android_sdk_path = C:\Users\clearrain\AppData\Local/Android/Sdk
export/android/java_sdk_path    = C:/Program Files/Eclipse Adoptium/jdk-17.0.19.10-hotspot
export/android/debug_keystore   = C:/Users/clearrain/AppData/Roaming/Godot/keystores/debug.keystore
export/android/debug_keystore_pass = android
```

---

## 3. 本次改动（`git diff` 只有两个文件）

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

## 4. 已验证的结果

用 CLI 无头导出并校验过（不是纸上谈兵）：

```
package: name='com.clearrain.chemicalcollision' versionCode='1' versionName='1.0.0'
application-label: '化学碰撞'
application-icon: res/mipmap-anydpi-v26/icon.xml     ← 自适应图标生效
minSdkVersion 24 / targetSdkVersion 36 / compileSdk 36
native-code: arm64-v8a
签名: APK Signature Scheme v2 + v3 通过
大小: 27.27 MB
```

产物：`C:\Users\clearrain\Documents\deepseek-harness\default-workspace\sdk-dl\chemical-debug.apk`
（APK 内部 `assets/` 已包含 `project.binary`、`*.gdc`、`backend/*.ctex`、`assets.sparsepck`——**手机只要传这一个 APK**，不像 Windows 要 exe + pck。）

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

2. **release keystore**（要上架 Google Play / 分发给别人时才需要）
   现在 `package/signed=true` 但没有 release 密钥，导 release 包会用 debug 密钥签，**不能上架**。
   ```powershell
   & "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\bin\keytool.exe" -genkeypair -v `
     -keystore D:\keys\chemical-release.keystore -alias chemical -keyalg RSA -keysize 2048 -validity 10000
   ```
   生成后填进导出面板 Android → 密钥库（或 `.godot/export_credentials.cfg` 的 `keystore/release*` 三项），**密钥务必备份，丢了就无法更新已上架应用**。

3. **模拟器测试**：预设只勾了 `arm64-v8a`，x86_64 模拟器装不上。要测模拟器就勾 `architectures/x86_64`（APK 会大 70 MB 左右）。

4. **局域网联机**：`scripts/net/` 目前只有 `LoopbackTransport`（进程内回环），没有 ENet 实现。等接 ENet 时，必须同时在预设里勾 **`permissions/internet`** 并重新导出，否则 Android 上网络请求会被系统拒绝。

5. **可选**：`application-label` 现在是「化学碰撞」，包名是 `com.clearrain.chemicalcollision`——这两个是可随时改的，但要趁没上架前定下来。

---

## 6. 常用命令

```powershell
$godot = "C:\Users\clearrain\Desktop\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe"
$proj  = "D:\Github_Library\Chemical\Chemical_Collision\chemical-1"
$sdk   = "C:\Users\clearrain\AppData\Local\Android\Sdk"

# 导出 debug APK（路径随便给，会覆盖预设里的 export_path）
& $godot --headless --path $proj --export-debug "Android" "D:\out\game-debug.apk"

# 导出 release APK（需要先配 release keystore）
& $godot --headless --path $proj --export-release "Android" "D:\out\game-release.apk"

# 导出 Windows（预设名是 "Chemical Collision"）
& $godot --headless --path $proj --export-release "Chemical Collision" "D:\out\game.exe"

# 查看 APK 信息 / 校验签名
& "$sdk\build-tools\36.0.0\aapt2.exe" dump badging "D:\out\game-debug.apk"
& "$sdk\build-tools\36.0.0\apksigner.bat" verify --verbose "D:\out\game-debug.apk"

# 装到手机
& "$sdk\platform-tools\adb.exe" install -r "D:\out\game-debug.apk"
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
| APK 在哪？ | 导出面板输出，或预设里 `…Export_Godot_Pack\Chemical Collision——pre1002.apk` |
| 为什么有两条渲染路径？ | 桌面 Forward+，移动端 GL 兼容（`rendering_method.mobile`） |
| 上架还缺什么？ | release keystore + 512×512 高清图标 + 定稿包名/应用名 |
| 现在能装吗？ | 能，debug 签名，需允许「未知来源」 |
| 换机器要重装什么？ | 4.7.2 导出模板 + Android SDK + JDK 17，然后在编辑器设置里指路径 |
