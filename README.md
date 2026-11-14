# DNA ULTRA

「与汝共奏 DNA」0.3.5 的深度定制版源码：**玻璃拟态界面 + 云端语音合成（直连厂商 API）+ 离线语音输入 + 可组合的提示词策略面板 + 应用内更新**。

本项目是第三方定制分支，基于上游 `netsince/DNA-APP` 的 0.3.5 源码修改而来，与上游作者无隶属或背书关系（详见文末「出处」）。

---

## 一、这一版改了什么

**界面**

- 全站玻璃质感（`LiquidGlass`）：卡片、会话行、输入栏、底部导航统一折射边 + 顶部高光；浅色主题自动降强度
- 侧栏换成品牌封面（星云 + 光晕 LOGO）
- 6 套配色 + 自定义画布/玻璃底色

**语音输出**

- 双模式：`直连厂商 API`（手机/桌面默认，Key 存本机）与 `本机语音服务`（可选）
- 桌面端用 Windows 自带 `winmm` MCI 播放 mp3，不再依赖 node 桥（体积从 162MB 降到 62MB）
- 按角色名匹配音色；语音分段合成边播边取，播完自动清缓存（默认上限 512MB）
- 修复「手机端直连模式没有朗读按钮」

**语音输入（离线）**

- sherpa-onnx 流式识别，`record` 采 16kHz 单声道 PCM，说话即转文字、自动断句
- 模型在应用内下载（ModelScope 国内源，默认/中英/英文/Paraformer 四款），存 `Documents/sherpa_models`
- Windows 端需要把 `sherpa_onnx_windows` 包里的 `onnxruntime.dll`、`sherpa-onnx-c-api.dll`、`sherpa-onnx-cxx-api.dll`、`onnxruntime_providers_shared.dll` 放到 exe 同级目录
- **坑（已绕过）**：`sherpa` 按 ORT API 28 编译，而系统 `C:\Windows\System32\onnxruntime.dll` 是 1.17 → 创建识别器会 0xC0000005。代码里先用完整路径 `DynamicLibrary.open` 预载包内 onnxruntime 再初始化

**提示词策略 v2**

- 三段式面板：5 个预设胶囊（电影感/网文爽/乙女向/悬疑本/日常向）→ 6 条主轴滑杆 → 20+ 组高级细项
- 覆盖：视角人称、情绪基调、张力曲线、关系闸门、称呼系统、硬约束（禁用词/口癖/不得替用户行动）、感官六通道、场景时序、信息揭示、主动性、叙事结构、冲突来源、语言密度、时代语境、物件焦点、收束钩子、群像 NPC
- 组合冲突自动降级并解释；右上角可预览「这套策略最终拼进系统提示的那一段」
- 只注入用户改过的组，默认配置几乎不加 token

**其它**

- 应用内更新：`update.json` 清单 + 下载 + 调系统安装器（安卓）/ 覆盖重启（桌面）
- 字体子集化（Source Han Sans 16MB → 5MB）、图标 WebP（6.2MB → 0.7MB）
- 设置页搜索、崩溃日志、启动耗时打点

## 二、构建

需要 Flutter 3.4x（本版在 3.47.9 / Dart 3.13.7 上验证）。

```bash
flutter pub get

# 安卓（arm64 单 ABI）
flutter build apk --release --target-platform android-arm64 --split-per-abi

# 桌面
flutter build windows --release
# 之后把 sherpa DLL 拷到 exe 同级目录（见上）
```

安卓包名 `com.netsince.dna`；`pubspec.yaml` 里 `version: 1.0.4+2104`，arm64 分包的 versionCode 会自动 +2000（4104）。

## 三、更新清单格式

放在你的更新地址根目录，应用内「设置 → 关于 → 应用内更新」填同一个地址即可：

```json
{
  "android": {
    "versionCode": 4104,
    "versionName": "1.0.4",
    "url": "https://example.com/update/app-release.apk",
    "notes": "改了什么"
  },
  "windows": {
    "version": "1.0.1",
    "url": "https://example.com/update/app-windows.zip",
    "notes": "解压后根目录或一层目录内是 dna.exe"
  }
}
```

安卓比 `versionCode`，桌面比 `version` 字符串。桌面的版本号读的是 exe 的 VERSIONINFO，改不了 runner 时**不要**把 windows 段写高，否则每次启动都提示更新。

## 四、语音合成（可选）

朗读走厂商 TTS 接口（默认兼容 `xi-api-key` + `POST /v1/text-to-speech/{voice_id}?output_format=mp3` 的厂商，如 Breeze Blue）。设置里填接口根地址与 API Key 即可，Key 只存本机。没有 Key 时朗读按钮会提示，不影响其它功能。

## 五、许可与出处

源码沿用上游 **nSPPL** 许可（`LICENSE-nSPPL`），字体/素材许可见 `LICENSE-OFL`、`LICENSE-CC`。

上游项目：「与汝共奏 Duet Nurturing Ally」，作者 netSince（https://github.com/netsince/DNA-APP）。本仓库是第三方定制分支，不暗示上游背书；上游名称仅用于说明来源。
