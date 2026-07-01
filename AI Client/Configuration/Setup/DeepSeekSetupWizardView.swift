import SwiftUI
import UIKit

struct DeepSeekSetupWizardView: View {
    private enum Step: CaseIterable {
        case connection
        case memory
    }

    private let onComplete: () -> Void
    @State private var draft = DeepSeekSetupDraft()
    @State private var step: Step = .connection
    @State private var showsAPIKey = false
    @State private var saveErrorMessage: String?
    @State private var showsSkipConfirmation = false

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    setupProgressIndicator
                    header

                    switch step {
                    case .connection:
                        connectionStep
                    case .memory:
                        memoryStep
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 34)
                .frame(maxWidth: 620, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: UIColor.systemGroupedBackground))
            .navigationTitle(step == .connection ? "连接 DeepSeek" : "隐私与拍照")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if step == .connection {
                        Button("跳过") {
                            showsSkipConfirmation = true
                        }
                    }
                }
            }
            .alert("跳过初始配置？", isPresented: $showsSkipConfirmation) {
                Button("取消", role: .cancel) {}
                Button("确认跳过", role: .destructive) {
                    skipSetup()
                }
            } message: {
                Text("你可以之后在设置里配置 Provider，并在设置中开启全局记忆/参考历史对话。")
            }
        }
    }

    private var setupProgressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { index in
                let segmentStep = Step.allCases[index]
                let isCompleted: Bool = {
                    switch step {
                    case .connection:
                        return false
                    case .memory:
                        return segmentStep == .connection
                    }
                }()
                let isCurrent = segmentStep == step
                Capsule()
                    .fill(
                        isCompleted || isCurrent
                        ? Color.accentColor
                        : Color(uiColor: UIColor.tertiaryLabel).opacity(0.4)
                    )
                    .frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(progressAccessibilityLabel))
    }

    private var progressAccessibilityLabel: String {
        switch step {
        case .connection:
            return "步骤 1/2：连接 DeepSeek"
        case .memory:
            return "步骤 2/2：隐私与拍照"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step == .connection ? "先把模型服务接上" : "再决定记忆与拍照偏好")
                .font(.system(size: 32, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(step == .connection
                 ? "Base URL 是服务地址，API Key 是你在 Provider 获取的访问密钥。先填好这两项，应用才知道把请求发到哪里。"
                 : "记忆功能可以让应用参考过去内容，但它需要把相关对话发送到你选择的 Provider 生成或更新记忆。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("1. 选择服务地址")
                    .font(.headline)

                Picker("Base URL", selection: $draft.baseURLChoice) {
                    ForEach(DeepSeekSetupDraft.BaseURLChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)

                if draft.baseURLChoice == .custom {
                    TextField("例如：https://api.deepseek.com", text: $draft.customBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(DeepSeekSetupCoordinator.officialBaseURL)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("2. 填写 API Key")
                    .font(.headline)
                Group {
                    if showsAPIKey {
                        TextField("粘贴你的 DeepSeek Key", text: $draft.apiKey)
                    } else {
                        SecureField("粘贴你的 DeepSeek Key", text: $draft.apiKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

                Toggle("显示 API Key", isOn: $showsAPIKey)
            }

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button {
                continueToMemoryStep()
            } label: {
                Text("继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!draft.canSaveConnection)
        }
        .padding(18)
        .background(Color(uiColor: UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var memoryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("隐私风险提示")
                    .font(.headline)
                Text("开启后，相关对话内容可能会在后台发送到你选择的 Provider，用于生成、更新或参考记忆。请不要在开启记忆时输入不希望被 Provider 处理的隐私内容。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Toggle("启用全局记忆", isOn: $draft.enablesMemory)

            Toggle("参考历史对话", isOn: $draft.enablesHistoryRecall)
                .disabled(!draft.enablesMemory)
                .onChange(of: draft.enablesMemory) { _, isEnabled in
                    if !isEnabled {
                        draft.enablesHistoryRecall = false
                    }
                }

            Toggle("保存拍摄的照片到相册", isOn: $draft.enablesSaveCapturedPhotosToLibrary)

            VStack(alignment: .leading, spacing: 6) {
                Text("拍摄的照片默认只在对话里使用，不会写入相册。")
                Text("开启后，拍照发送时会同时把原图保存到你的系统相册；在临时聊天中始终不会保存。")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                Button {
                    finishSetup(enablesMemory: draft.enablesMemory)
                } label: {
                    Text(draft.enablesMemory ? "保存并进入主界面" : "进入主界面")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(18)
        .background(Color(uiColor: UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func continueToMemoryStep() {
        var configurations = AIConfigurationStore.loadConfigurations()
        var selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()

        guard DeepSeekSetupCoordinator.applyConnection(
            draft: draft,
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID
        ), AIConfigurationStore.saveConfigurations(configurations) else {
            saveErrorMessage = "保存失败，请稍后再试。"
            return
        }

        if let selectedConfigurationID {
            AIConfigurationStore.saveSelectedConfigurationID(selectedConfigurationID)
        }

        saveErrorMessage = nil
        step = .memory
    }

    private func skipSetup() {
        onComplete()
    }

    private func finishSetup(enablesMemory: Bool) {
        draft.enablesMemory = enablesMemory
        if !enablesMemory {
            draft.enablesHistoryRecall = false
        }
        DeepSeekSetupCoordinator.applyMemoryPreferences(draft: draft)
        onComplete()
    }
}
