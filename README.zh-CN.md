<div align="center">
  <img src="AI%20Client/Assets.xcassets/MewyAILogo.imageset/MewyAI.png" alt="MewyAI 标志" width="128">

  <h1>MewyAI</h1>

  <p>一款面向 iPhone 与 iPad 的原生 BYOK AI 客户端。</p>

  <p><a href="README.md">English</a></p>

  <p>
    <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
    <img src="https://img.shields.io/badge/iOS-17.0%2B-000000?logo=apple&logoColor=white" alt="iOS 17.0 或更高版本">
    <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
    <img src="https://img.shields.io/badge/version-1.1.0-2ea44f" alt="版本 1.1.0">
    <img src="https://img.shields.io/badge/license-All%20rights%20reserved-lightgrey" alt="保留所有权利">
  </p>

  <p>
    <a href="#功能">功能</a> ·
    <a href="#快速开始">快速开始</a> ·
    <a href="Docs/architecture.md">架构</a> ·
    <a href="Docs/privacy.md">隐私</a> ·
    <a href="CONTRIBUTING.md">贡献指南</a>
  </p>
</div>

MewyAI 是一款独立开发的原生 iOS AI 客户端，采用自带密钥（BYOK）模式。项目探索了多 Provider 模型集成、流式响应、本地会话存储、工具调用，以及功能完整的 SwiftUI AI 客户端架构。

> [!IMPORTANT]
> 此仓库是从原本私有开发的项目中整理出的公开发布版本。目前处于维护模式，仅供技术审查、作品集展示与有限维护之用，并非活跃的商业开发项目。

## 功能

| 聊天体验 | Provider 与模型 |
| --- | --- |
| 流式响应与多会话管理 | OpenAI Chat Completions 与 Responses |
| Markdown、语法高亮、表格与 LaTeX | Anthropic Messages 与 Vertex AI Express |
| 图片和文档附件、相机与语音输入 | OpenAI 兼容的自定义 Provider |
| 消息编辑、分支、搜索与导出 | 多 API Key 与本地故障切换状态 |

| 本地数据 | 工具与集成 |
| --- | --- |
| SQLite 会话持久化 | 模型工具调用及 Skills/MCP 支持 |
| 本地知识库索引与检索 | App Intents 与 Apple 平台集成 |
| API Key 与敏感请求头存储于 Keychain | 后台完成通知 |
| 本地用量与费用估算 | 自定义基础 URL 与请求头 |

Provider 与模型的实际行为因 API 实现而异。列出的预设不代表对任何 Provider 或其模型的背书、关联关系或兼容性保证。

## 项目状态

MewyAI 的一个版本曾在私有开发期间通过 App Store 审核并发布。本仓库不声明其当前仍在 App Store 上架，也不会更改任何生产环境的 App Store 版本。

| | |
| --- | --- |
| **App 版本** | 1.1.0（构建版本 7） |
| **最低部署目标** | iOS 17.0 |
| **语言** | Swift 6 |
| **界面** | SwiftUI，搭配部分 UIKit 集成 |
| **项目** | `AI Client.xcodeproj` |
| **Scheme** | `AI Client` |
| **App target / 模块** | `MewyAI` |
| **测试 target** | `MewyAITests` |

## 快速开始

### 要求

- 安装支持 Swift 6 和 iOS 17 SDK 的 Xcode 的 macOS
- 首次解析 Swift Package Manager 依赖时需要互联网连接
- 安装到真机时，需要使用你自己的 Apple 开发者团队

### 构建

克隆仓库后，打开 `AI Client.xcodeproj`。Xcode 会从 `Package.resolved` 恢复已锁定版本的 Swift Package。

不进行代码签名的构建：

```sh
xcodebuild -project 'AI Client.xcodeproj' \
  -scheme 'AI Client' \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

构建 App 与测试包，但不启动模拟器：

```sh
xcodebuild build-for-testing \
  -project 'AI Client.xcodeproj' \
  -scheme 'AI Client' \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

如需安装到设备，请选择你自己的开发者团队，并使用归你所有的 bundle identifier。公开项目刻意不包含 Apple Developer Team ID。[`Secrets.example.xcconfig`](Secrets.example.xcconfig) 包含仅供参考的无效签名占位符，项目不会自动加载它。

> [!NOTE]
> 重新分发构建产物前，请将 `AI Client/App/Onboarding/OnboardingConsentView.swift` 中刻意设为无效的 `support@example.invalid` 地址替换为有人维护的公开支持邮箱。

### 添加 API Key

构建时不需要任何 Provider Key。

1. 启动 App，打开 Provider 配置界面。
2. 添加或选择一个 Provider，并确认其基础 URL 与协议。
3. 输入你自己的 API Key，以及任何需要的敏感自定义请求头。
4. 添加或获取模型标识符，并测试该配置。

Provider API Key、Agent 密钥与敏感自定义请求头值会以通用密码项目的形式存储于 iOS Keychain，并使用 `WhenUnlockedThisDeviceOnly` 可访问性。非敏感配置元数据会单独存储。绝不要将 Provider Key 放入源文件、`.xcconfig` 文件、测试、截图或 issue 报告中。

## 架构

App 围绕清晰的功能与服务边界组织：

```text
AI Client/
├── App, Chat             SwiftUI 展示层与聊天会话状态
├── AIService             Provider 请求与流式响应解析
├── Configuration         Provider、模型与凭据元数据
├── Persistence           本地 SQLite 会话存储
├── Agent, MCP            工具能力与编排
├── KnowledgeBase         本地文档处理与检索
├── AppIntents            Apple 平台集成
└── SharedUI              可复用界面组件
```

完整的数据流和安全边界请见 [Docs/architecture.md](Docs/architecture.md)。

### 支持的协议

| 协议 | 常见用途 |
| --- | --- |
| OpenAI Chat Completions | OpenAI 与 OpenAI 兼容的聊天 API |
| OpenAI Responses | 与 OpenAI Responses 兼容的 API |
| Anthropic Messages | 与 Claude 兼容的消息 API |
| Vertex AI Express | 通过 Vertex Express API 访问 Gemini 模型 |

支持自定义基础 URL 和请求头。请将自定义端点视为独立的信任边界：提示词、附件和已召回的上下文都会被发送至该请求所选的端点。

## 隐私与安全

会话与知识库数据存储在 App 的 Application Support 目录中。需要请求时，内容会传输给用户选定的 Provider 或自定义端点。本地数据库无法提供等同于 Keychain 的保护，因此不应将设备视为零信任存储环境。

- [隐私与数据清单](Docs/privacy.md)
- [安全策略与漏洞报告](SECURITY.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

## 截图

经审核的公开截图尚未提交。请参阅[截图脱敏与采集清单](Docs/screenshots/README.md)。合成截图和私有测试会话不能作为替代品。

## 已知限制

- BYOK API 可独立于本维护型仓库发生变化。
- Vertex AI Express 不会自动发现模型；模型 ID 需要手动添加。
- 工具调用、推理字段、用量报告和图片支持取决于所选的 Provider 与模型。
- 本地会话和知识库文件未使用应用层端到端加密。
- App Store 二进制版本可能与最新公开源代码快照不同。
- 项目不保证响应时限，也不承诺提供商业支持。

## 贡献

提交 issue 或 pull request 前，请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，并查看[变更历史](CHANGELOG.md)。请勿在报告中包含 API Key、私有会话或其他敏感信息。

## 许可证

MewyAI 由 **SharkyMew** 开发。经整理的 Git 历史保留了提交作者与日期。

MewyAI 源代码采用**保留所有权利**许可证提供，并非开源许可证。请见 [LICENSE](LICENSE)。随附依赖仍受其各自许可证约束。
