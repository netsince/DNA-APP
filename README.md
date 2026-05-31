<p align="center">
    <a href="https://dnaopensourse.netsince.com" target="_blank">
        <img src="assets/screenshots/b.png" alt="与汝共奏 - Duet Nurturing Ally 项目 LOGO"/>
    </a>
</p>

<h1 align="center">🎵 与汝共奏 - Duet Nurturing Ally (DNA)</h1>

<div align="center">

**开源 · 数据本地 · 隐私优先的角色扮演 APP**

</div>

<div align="center">
    <a href="https://dnaopensourse.netsince.com">🌐 项目官网</a>
    <span> • </span>
    <a href="https://dnaopensourse.netsince.com/download">📥 下载</a>
    <span> • </span>
    <a href="https://dnaopensourse.netsince.com/park">🔍 查找角色卡</a>
    <span> • </span>
    <a href="https://github.com/netsince/DNA-PARK">🏞️ 社区开源</a>
</div>

<br>

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
![License-nSPPL](https://img.shields.io/badge/License-nSPPL-4B0082)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-6DB33F)
![Version](https://img.shields.io/badge/Version-1.0.0-blue)

</div>

---

## 📋 目录

- 普通用户请看
- [📸 截图预览](#-截图预览)
- [📖 项目故事](#-项目故事)
- [🔒 隐私保障：无多余网络请求](#-隐私保障无多余网络请求)
- [🏞️ 社区](#️-社区)
- [✨ 特性](#-特性)
- FOR DEVELOPERS:
- [🚀 快速开始（开发者）](#-快速开始开发者)
- [📦 构建](#-构建)
- [🔗 相关链接](#-相关链接)
- [📄 许可证](#-许可证)

---

## 📸 截图预览

![首页 — 极简，任我玩](assets/screenshots/main.png)
![启动向导 — 三步，这就好](assets/screenshots/OOBEs.png)
![聊天 — 对话，在本地](assets/screenshots/chat.png)
![角色设定 — 设定，也本地](assets/screenshots/character.png)
![设置 — 设置，很个性](assets/screenshots/settings.png)

---

## 📖 项目故事

最初只是因为一款市面上"名字里有 Max 旗下、且名字跟《蔚蓝档案》某个角色重名"的软件——功能冗余又圈钱、评论区混乱、推荐系统糟糕、违禁词多如牛毛，而我只想要纯粹的角色扮演体验。

一气之下，自己动手写了这个软件，让自己玩爽了。

到了后期，随着相关政策的出台，大部分的 角色扮演 软件都炸了

我想了想，不如...直接开源！我又做了一些调整，约了个 LOGO，索性将其开源——**我要让各位都玩爽！**

这，就是这个项目的由来。

> 💡 名称由来：简称 **DNA** 既取自项目英文名 **D**uet **N**urturing **A**lly，也双关了生物学中的 DNA（脱氧核糖核酸），同时 Cue 了游戏《二重螺旋》。

---

## 🏞️ 社区

有社区，但是单独的网站。

我们希望社区是跟APP解耦的，虽然这样有些麻烦。

当然，社区也是开源的！[DNA-PARK](https://github.com/netsince/DNA-PARK)

## 🔒 隐私保障：无多余网络请求

**核心原则：除了您指定的 API 和设置设置的，应用在运行中不会连接到任何第三方网络。**

- 所有对话数据、角色设定、世界设定均存储在您的设备本地（后续可能支持上传到GitHub备份，当然也是可选的，但以后的事情以后说）
- 如果您使用本地模型（如 Ollama、llama.cpp 等），甚至可以做到 **完全零网络请求**

---

## ✨ 特性

- **🔐 数据本地存储** — 所有对话数据存储在本地，不会无理由传到任何第三方服务器
- **📡 零多余网络请求** — 除请求指定的 API、设置外，不会连接任何第三方网络（可选搭配本地模型实现完全离线）
- **🎭 角色扮演体验** — 专注于纯粹的 RP（Role-Play）体验，无冗余功能干扰
- **📋 灵活的提示词策略** — 支持自定义提示词策略，精细控制 AI 角色行为
- **🌓 动态主题** — 支持动态色彩主题，跟随系统亮暗模式自动切换
- **🔒 本地身份验证** — 支持本地生物识别锁定，保护隐私数据
- **🖥️ 跨平台** — 支持 Android、iOS、Windows、macOS、Linux

# FOR DEVELOPERS
## 🚀 快速开始（开发者）

### 前置要求

- [Flutter SDK](https://docs.flutter.dev/get-started/install)（版本要求见 `pubspec.yaml` 中的 `environment.sdk`）
- 对应平台的开发工具（Android Studio / Xcode / Visual Studio 等）

### 运行

```bash
# 克隆仓库
git clone https://github.com/netsince/dna-client.git
cd dna-client

# 获取依赖
flutter pub get

# 运行（选择目标平台）
flutter run
```

### 配置 API

在应用的设置页面中配置您的 API 地址和密钥，支持任何兼容 OpenAI 协议的 API 服务（包括本地模型）。

---

## 📦 构建

```bash
# Android APK
flutter build apk

# iOS
flutter build ios

# Windows
flutter build windows

# macOS
flutter build macos

# Linux
flutter build linux

# Web
flutter build web
```

---

## 🔗 相关链接

- [项目官网](https://dnaopensourse.netsince.com)
- [下载页面](https://dnaopensourse.netsince.com/download)
- [角色卡社区](https://dnaopensourse.netsince.com/park)
- [社区开源仓库 (DNA-PARK)](https://github.com/netsince/DNA-PARK)

---

## 📄 许可证

- **源代码**：[netSince.com PPL](LICENSE-nSPPL)
- **美术资源（如 LOGO）**：[CC BY-NC-ND 4.0](LICENSE-CC)
