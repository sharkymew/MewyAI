import SwiftUI
import UIKit

struct OnboardingConsentView: View {
    private let onAgree: () -> Void
    @State private var showsDisagreeAlert = false

    init(onAgree: @escaping () -> Void) {
        self.onAgree = onAgree
    }

    var body: some View {
        ZStack {
            Color(uiColor: UIColor.systemGray5)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 70)

                VStack(spacing: 24) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            title
                            introduction
                            featureRows
                            policyNotice
                        }
                        .padding(.horizontal, 34)
                        .padding(.top, 54)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)

                    actionButtons
                        .padding(.horizontal, 34)
                        .padding(.bottom, 34)
                }
                .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(uiColor: UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .alert("暂时无法继续", isPresented: $showsDisagreeAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("必须阅读并同意用户协议与隐私政策后，才能继续使用本客户端。")
        }
    }

    private var title: some View {
        Text("欢迎使用\nMewyAI")
            .font(.system(size: 42, weight: .heavy))
            .lineSpacing(2)
            .lineLimit(nil)
            .minimumScaleFactor(0.78)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.init("欢迎使用本客户端，在使用前请阅读并同意我们的[《用户协议 (EULA)》](https://app.notion.com/p/MewyAI-EULA-38b60bf3841180c98c36c4d2880bed37)和[《隐私政策》](https://app.notion.com/p/MewyAI-38a60bf38411807aa8f3c35341856342)。"))
            .font(.headline)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureRows: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingFeatureRow(
                systemImage: "key.fill",
                title: "连接你的 Provider",
                message: "下一步会带你填写 DeepSeek 地址和 API Key。"
            )
            OnboardingFeatureRow(
                systemImage: "lock.shield.fill",
                title: "先理解隐私选项",
                message: "记忆功能默认关闭，只有你明确开启后才会工作。"
            )
            OnboardingFeatureRow(
                systemImage: "checkmark.seal.fill",
                title: "确认合规使用",
                message: "请只在合法、合规、尊重他人的场景中使用。"
            )
        }
    }

    private var policyNotice: some View {
        Text("本工具禁止用于生成任何涉黄、涉暴、侮辱性或政治敏感等违法违规内容。")
            .font(.headline.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onAgree()
            } label: {
                Text("同意并继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                showsDisagreeAlert = true
            } label: {
                Text("不同意")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

private struct OnboardingFeatureRow: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
