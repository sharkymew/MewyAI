<div align="center">
  <img src="AI%20Client/Assets.xcassets/MewyAILogo.imageset/MewyAI.png" alt="MewyAI 标志" width="128">

  <h1>MewyAI</h1>

  <p>一款面向 iPhone 与 iPad 的原生、本地优先 BYOK AI 客户端。</p>

  <p><a href="README.md">English</a></p>

  <p>
    <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
    <img src="https://img.shields.io/badge/iOS-17.0%2B-000000?logo=apple&logoColor=white" alt="iOS 17.0 或更高版本">
    <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
    <img src="https://img.shields.io/badge/version-1.1.0-2ea44f" alt="版本 1.1.0">
    <img src="https://img.shields.io/badge/license-Source--Available-lightgrey" alt="源码可见的专有许可证">
  </p>

  <p>
    <a href="#功能">功能</a> ·
    <a href="#快速开始">快速开始</a> ·
    <a href="Docs/architecture.md">架构</a> ·
    <a href="Docs/privacy.md">隐私</a> ·
    <a href="CONTRIBUTING.md">问题反馈</a>
  </p>
</div>

MewyAI 是一款独立开发的原生 iOS AI 客户端，采用自带密钥（BYOK）模式，并使用 Swift 6、SwiftUI 与部分 UIKit 开发。公开源代码展示了多 Provider 请求、本地会话与知识库数据、流式响应、工具调用及 Apple 平台集成等实现范围。

> [!IMPORTANT]
> **源码公开可见，但 MewyAI 并非开源软件。** 本仓库依据源码可见的专有许可证发布；仅允许在遵守 [LICENSE](LICENSE) 的前提下，为非商业个人评估或个人教育学习查看源代码并在本地运行未修改副本。构建或运行严格必需的有限配置变更（例如填写个人 API Key、修改本地签名信息或设置归自己所有的 bundle identifier）以 LICENSE 完整条款为准。未经版权所有者事先书面许可，不得进行其他修改、分发、重新发布、部署、托管、商业使用或制作衍生作品。

## 功能

| 聊天与内容 | Provider 与协议 |
| --- | --- |
| 流式响应与多会话管理 | OpenAI Chat Completions 与 OpenAI Responses |
| Markdown、语法高亮、表格与 LaTeX | Anthropic Messages 与 Vertex AI Express |
| 图片与文档附件、相机与语音输入 | OpenAI 兼容的自定义 Provider |
| 消息编辑、分支、搜索与导出 | 多 API Key 与本地故障切换状态 |

| 本地数据与配置 | 工具与平台集成 |
| --- | --- |
| SQLite 会话持久化 | 模型工具调用与 Skills/MCP |
| 本地知识库索引与检索 | App Intents 与 Apple 平台集成 |
| API Key 与敏感请求头的 Keychain 存储 | 后台完成通知 |
| 本地用量与费用估算 | 自定义基础 URL 与请求头 |

功能列表描述的是公开源代码中可审查的实现范围，不代表每项能力都适用于所有 Provider、模型、设备或系统版本。Provider 与模型的实际行为取决于具体 API 实现；列出的预设不表示背书、关联关系或兼容性保证。Agent、MCP、知识库及部分后台行为应视为实验性能力。

## 项目状态

本仓库来自私有开发项目整理后的公开版本，目前处于维护模式，主要用于技术审查与作品集展示；它不是持续迭代的商业产品。维护者可自行决定进行必要修复，但不承诺持续开发、功能更新、响应时限或商业支持。

MewyAI 的一个版本曾在私有开发期间通过 App Store 审核并发布；本仓库不表示该版本目前仍在 App Store 提供，也不与任何历史或现存生产版本保持自动同步。

| | |
| --- | --- |
| **App 版本** | 1.1.0（构建版本 7） |
| **最低部署目标** | iOS 17.0 |
| **语言** | Swift 6 |
| **界面** | SwiftUI，搭配部分 UIKit 集成 |
| **项目** | <code>AI Client.xcodeproj</code> |
| **Scheme** | <code>AI Client</code> |
| **App target / 模块** | <code>MewyAI</code> |
| **测试 target** | <code>MewyAITests</code> |

## 快速开始

### 要求

- 运行 macOS，且已安装支持 Swift 6 和 iOS 17 SDK 的 Xcode
- 首次解析 Swift Package Manager 依赖时需要互联网连接
- 安装到真机时需要使用自己的 Apple 开发者团队与归自己所有的 bundle identifier

### 本地构建

克隆、构建和运行本仓库均须遵守 [LICENSE](LICENSE)，并且仅限许可证允许的非商业个人评估和个人教育学习。克隆仓库后，打开 <code>AI Client.xcodeproj</code>；Xcode 会从 <code>Package.resolved</code> 恢复锁定版本的 Swift Package。

不进行代码签名的构建：

~~~sh
xcodebuild -project 'AI Client.xcodeproj' \
  -scheme 'AI Client' \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
~~~

构建 App 与测试包，但不启动模拟器：

~~~sh
xcodebuild build-for-testing \
  -project 'AI Client.xcodeproj' \
  -scheme 'AI Client' \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
~~~

如需安装到真机，请选择自己的 Apple 开发者团队，并使用归自己所有的 bundle identifier。公开仓库刻意不包含 Apple Developer Team ID。[Secrets.example.xcconfig](Secrets.example.xcconfig) 仅包含无效示例占位符，项目不会自动加载它。

> [!NOTE]
> <code>AI Client/App/Onboarding/OnboardingConsentView.swift</code> 中的 <code>support@example.invalid</code> 是刻意设置的无效占位地址，仅用于许可证允许范围内的本地构建与个人评估。当前许可证不授予重新分发编译产物的权利；替换该地址并不构成任何分发授权。

### 添加 API Key

构建项目不需要任何 Provider API Key。API Key 由用户在 App 内配置：

1. 启动 App，打开 Provider 配置界面。
2. 添加或选择 Provider，并确认其基础 URL 与协议。
3. 输入自己的 API Key，以及任何需要的敏感自定义请求头。
4. 添加或获取模型标识符，并测试该配置。

Provider API Key、Agent 密钥和敏感自定义请求头值会以通用密码项目形式存储于 iOS Keychain，并使用 <code>WhenUnlockedThisDeviceOnly</code> 可访问性；非敏感配置元数据会单独存储。这表示凭据可在设备解锁时由 App 访问，且不会迁移到另一台设备。请勿将密钥写入源代码、<code>.xcconfig</code>、测试、截图或 issue 报告中。

## 架构

App 围绕清晰的功能与服务边界组织：

~~~text
AI Client/
├── App, Chat             SwiftUI 展示层与聊天会话状态
├── AIService             Provider 请求与流式响应解析
├── Configuration         Provider、模型与凭据元数据
├── Persistence           本地 SQLite 会话存储
├── Agent                 工具能力、MCP 与 Skills 编排
├── KnowledgeBase         本地文档处理与检索
├── AppIntents            Apple 平台集成
└── SharedUI              可复用界面组件
~~~

完整的数据流与安全边界请见 [Docs/architecture.md](Docs/architecture.md)。

### 支持的协议

| 协议 | 常见用途 |
| --- | --- |
| OpenAI Chat Completions | OpenAI API 及实现兼容接口的自定义端点 |
| OpenAI Responses | OpenAI Responses API 及其兼容实现 |
| Anthropic Messages | Anthropic Messages API 及其兼容实现 |
| Vertex AI Express | 通过 Vertex AI Express 访问受支持的 Gemini 模型 |

支持自定义基础 URL 和请求头。自定义端点构成独立的信任边界：提示词、附件和召回上下文会发送至当前请求所选择的端点。文中提及的第三方名称和商标归其各自权利人所有；列举它们不表示 MewyAI 获得背书或与其存在关联。

## 隐私与安全

会话与知识库数据存储在 App 的 Application Support 目录中。进行模型请求时，内容会发送给用户选择的 Provider 或自定义端点。

会话与知识库数据不具有与 Keychain 凭据相同的保护边界。请勿将本 App 视为保存高度敏感信息的安全保险库，并应依赖设备密码、系统更新及操作系统提供的数据保护机制。本地会话和知识库文件没有应用层端到端加密。

- [隐私与数据清单](Docs/privacy.md)
- [安全策略与漏洞报告](SECURITY.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

## 截图

当前仓库暂不提供未经审核的开发截图。公开截图需要按照[截图脱敏与采集清单](Docs/screenshots/README.md)审查，以避免泄露 API Key、私人会话、设备信息或其他测试数据。

## 已知限制

- BYOK API 可独立于本仓库发生变化。
- Vertex AI Express 不会自动发现模型；模型 ID 需要手动添加。
- 工具调用、推理字段、用量报告和图片支持取决于所选 Provider 与模型。
- 自定义 Provider 的兼容程度取决于其 API 实现。
- Agent、MCP、知识库和部分后台能力属于实验性功能。
- 本地会话和知识库文件没有应用层端到端加密。
- App Store 二进制版本可能与公开源代码快照不同。
- 项目不保证响应时限，也不承诺商业支持。

## 问题反馈

可以按照 [CONTRIBUTING.md](CONTRIBUTING.md) 提交 issue、缺陷报告和功能建议，并查看[变更历史](CHANGELOG.md)。安全漏洞应按照 [SECURITY.md](SECURITY.md) 报告。

请勿在报告中包含 API Key、私有会话、个人数据、设备标识符或其他敏感信息。除非事先获得版权所有者书面许可，项目目前不接受包含代码修改的外部 pull request。提交 issue、建议或漏洞报告，不构成对修改、分发、Fork 或制作衍生作品的授权。

## 许可证

MewyAI 由 **SharkyMew** 开发；整理后的 Git 历史保留原有提交作者与日期。

本仓库采用[源码可见的专有许可证](LICENSE)，并非开源软件。许可证允许查看源代码，并在非商业个人评估或个人教育学习范围内本地运行未修改副本；构建或运行严格必需的有限配置变更以 LICENSE 的完整条款为准。

未经版权所有者事先书面许可，不得进行其他修改、分发、重新发布、托管、部署、商业使用或制作衍生作品。第三方依赖仍受其各自许可证约束，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。如本 README 的摘要与 LICENSE 完整条款不一致，以 LICENSE 为准。
