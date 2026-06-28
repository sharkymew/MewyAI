import SwiftUI
import UIKit

struct OnboardingConsentView: View {
    private let onAgree: () -> Void
    @State private var showsDisagreeAlert = false
    @State private var showsAgreementAlert = false

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
                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 24) {
                            title
                            agreementCard
                                .frame(height: agreementCardHeight(for: proxy.size.height))
                            Spacer(minLength: 0)
                            actionButtons
                        }
                        .padding(.horizontal, 34)
                        .padding(.top, 54)
                        .padding(.bottom, 34)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
        .alert("许可与条款", isPresented: $showsAgreementAlert) {
            Button("好") {
                onAgree()
            }
        } message: {
            Text("我已经认真阅读并认可所有协议文本。")
        }
    }

    private var title: some View {
        Text("欢迎使用 MewyAI")
            .font(.system(size: 42, weight: .heavy))
            .lineSpacing(2)
            .lineLimit(nil)
            .minimumScaleFactor(0.78)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var agreementCard: some View {
        let cardBackground = Color(uiColor: UIColor.secondarySystemGroupedBackground)

        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    policyNotice
                    legalSection(title: "MewyAI 隐私政策", text: privacyPolicyText)
                    Divider()
                    legalSection(title: "MewyAI 用户服务协议与最终用户许可协议 (EULA)", text: userAgreementText)
                }
                .padding(20)
            }
            .scrollIndicators(.visible)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [cardBackground, cardBackground.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)

                Spacer()

                LinearGradient(
                    colors: [cardBackground.opacity(0), cardBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: UIColor.separator).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func agreementCardHeight(for availableHeight: CGFloat) -> CGFloat {
        min(440, max(280, availableHeight - 250))
    }

    private func legalSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.bold))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var policyNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("合规使用提示")
                .font(.subheadline.weight(.bold))
            Text("本工具禁止用于生成、传播、存储或处理任何涉黄、涉暴、赌博、恐怖、教唆犯罪、侮辱诽谤、侵权、政治敏感或其他违法违规内容。请仅在合法、合规、尊重他人权益的场景中使用。")
                .font(.footnote.weight(.semibold))
                .lineSpacing(3)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.primary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showsAgreementAlert = true
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

    private let privacyPolicyText = """
更新日期：2026年6月28日

MewyAI（以下简称“本应用”）是一款独立的第三方大模型 API 客户端。我们深知隐私对您的重要性，并全力保护您的个人数据安全。本隐私政策阐明了我们在您使用本应用时处理数据的方式。

1. 数据收集与存储

- API 密钥（API Keys）：本应用采用“自备密钥（BYOK）”模式。您在应用内输入的任何 API 密钥（包括但不限于 DeepSeek、OpenRouter、OpenAI 等供应商的 Key）均直接存储在您本地设备的受保护区域（如 Keychain 或本地加密沙盒）中。
- 聊天记录：您的所有对话、提示词及交互历史均完全存储在您的本地设备中。本应用没有、也不会建立任何中央服务器来收集或读取您的聊天内容。

2. 数据的传输与第三方处理

- 大模型供应商请求：当您在应用内发起对话时，本应用会将您的提示词（Prompts）以及您提供或配置的 API 密钥，直接通过标准的加密通道（HTTPS/TLS）发送至您所选定的第三方大模型供应商接口（如 api.deepseek.com）。
- 免责声明：第三方大模型供应商对您数据的使用和保留策略，请参阅对应供应商的隐私政策（例如《DeepSeek 隐私政策》）。本应用不对第三方服务商的数据处理行为承担责任。
- 无其他第三方集成：本应用未集成任何第三方广告、追踪器或臃肿的数据分析统计 SDK。
- 记忆和参考过去的对话：应用可能会根据您过去的对话作为上下文参考，在您发起请求时将必要的前序对话数据发送至您设定的 API 提供商以实现连续对话或长期记忆。该功能完全由本地代码触发，可在设置中手动关闭，所有的记忆片段仅安全保存在您的本地设备中。

3. 数据删除

由于所有数据均保存在您的本地设备上，您可以通过随时卸载本应用或在设置中删除对应的 API 密钥，来彻底销毁和删除您的所有本地数据。

4. 政策更新

我们可能会不时更新本隐私政策。任何更改都将直接在本页面或应用内进行公示。

5. 联系我们

如果您对本隐私政策有任何疑问，欢迎通过以下方式与开发者取得联系：

- 电子邮件：support@example.invalid
"""

    private let userAgreementText = """
版本生效日期：2026年6月27日

欢迎您使用 MewyAI 客户端软件（以下简称“本软件”）。

本协议是您（以下亦称“用户”）与 MewyAI 开发者（以下简称“我们”）之间，就您下载、安装、访问和使用本软件所订立的法律协议。在您首次打开本软件并点击“同意并继续”之前，请您仔细阅读并理解本协议的全部内容，特别是与免责声明、第三方服务、内容合规、隐私与凭据安全、责任限制以及争议解决有关的条款。

如果您不同意本协议的任何内容，请不要继续安装、访问或使用本软件。

一、软件定位与服务说明

1. 本软件是一款纯本地效率工具及独立客户端软件。软件本身不内置、不提供、不销售任何人工智能模型、算力资源或 API 额度。
2. 本软件采用 BYOK（Bring Your Own Key）模式。用户需要自行在受支持的第三方 AI 平台或服务提供方获取合法、有效的 API 密钥、访问凭据或接口地址，并在本软件中自行配置后，方可使用相应的聊天、生成或相关功能。
3. 用户应确保其获取、配置和使用的 API Key、接口地址、中转代理或其他访问凭据来源合法、授权有效，并符合相关第三方平台的服务条款、使用政策及适用法律法规。因用户使用非官方、未经授权、非法中转、盗用、泄露或来源不明的 API 凭据所产生的法律责任、经济损失、账号限制、服务中断或其他风险，由用户自行承担。
4. 用户因使用第三方 API、第三方模型、第三方平台或自定义代理服务而产生的费用、调用限制、服务中断、内容输出、账号封禁、技术故障或其他纠纷，应由用户与相应第三方服务提供方自行解决。在法律允许的范围内，我们不对第三方服务的可用性、稳定性、准确性、安全性或合规性作出任何保证。

二、未成年人使用

1. 本软件可供用户在遵守本协议及适用法律法规的前提下使用。未成年人使用本软件时，建议在监护人的指导和监督下进行。
2. 若您为未满 14 周岁的儿童，请在监护人陪同下共同阅读本协议，并在取得监护人同意后使用本软件。
3. 监护人应合理引导未成年人正确使用本软件及第三方 AI 服务，避免未成年人接触不适宜内容，或进行可能违反法律法规、第三方服务规则及本协议的操作。

三、用户行为规范与 AIGC 合规条款

1. 用户在使用本软件及通过本软件调用第三方 AI 服务时，应遵守中华人民共和国法律法规、所在地区适用法律法规、第三方服务平台规则以及应用商店相关规范。
2. 用户不得利用本软件生成、传播、存储、处理或协助生成以下违法或明显不当内容：

（1）反对宪法所确定的基本原则的内容；
（2）危害国家安全，泄露国家秘密，颠覆国家政权，破坏国家统一的内容；
（3）损害国家荣誉和利益的内容；
（4）煽动民族仇恨、民族歧视，破坏民族团结的内容；
（5）破坏国家宗教政策，宣扬邪教和封建迷信的内容；
（6）散布谣言，扰乱社会秩序，破坏社会稳定的内容；
（7）散布淫秽、色情、赌博、暴力、凶杀、恐怖或者教唆犯罪的内容；
（8）侮辱、诽谤他人，或者侵害他人名誉权、隐私权、肖像权、知识产权及其他合法权益的内容；
（9）侵犯他人商业秘密、个人信息权益或其他合法权益的内容；
（10）含有法律、行政法规、部门规章或适用监管规则禁止的其他内容。

3. 若用户发现第三方 AI 服务返回的内容存在违法、侵权或明显不当信息，用户可以使用本软件提供的“隐藏”功能进行本地处理，并应避免继续传播、发布或以其他方式扩散相关内容。
4. 本软件仅作为用户访问第三方 AI 服务的本地客户端工具。第三方 AI 服务的输出内容可能存在错误、不完整、不准确、过时、偏见、冒犯性或不适当之处。用户应自行判断相关内容的准确性、合法性和适用性，不应将 AI 生成内容直接作为医疗、法律、金融、教育升学、安全决策或其他重要事项的唯一依据。

四、不当内容本地处理机制

1. 为协助用户管理第三方 AI 服务返回的内容，并满足应用商店有关用户生成内容及人工智能生成内容的合规要求，本软件提供本地内容隐藏功能。
2. 用户可以在聊天界面中，通过长按、点击菜单或其他软件内提供的方式，对指定的 AI 生成内容进行“隐藏”操作。
3. 用户触发“隐藏”操作后，本软件将在客户端本地对相应内容进行隐藏或清除。由于本软件为本地客户端工具，该操作不会向我们上传相关聊天内容或隐藏记录。
4. 隐藏功能仅用于用户在本地设备上管理显示内容，不代表我们对第三方 AI 生成内容进行了事前审查、人工审核、事实核验或法律判断。
5. 在法律允许的范围内，对于第三方 AI 模型独立生成的内容及由此产生的争议，我们不承担审查、控制、担保或赔偿责任。但如因本软件自身存在故意或重大过失导致用户合法权益受损的，将依照适用法律承担相应责任。

五、隐私与凭据安全

1. 我们重视用户隐私和凭据安全。您在本软件中输入的 API Key、自定义代理地址、模型配置、聊天记录及其他使用数据，默认存储于您的本地设备中；如您主动启用系统级或平台级同步功能，相关数据可能存储于您个人控制或授权使用的 iCloud 等云同步空间中。
2. 本软件不会主动将您的 API Key、聊天内容、自定义代理地址或其他敏感数据上传至我们控制的中央服务器。
3. 本软件发起的 AI 请求将根据用户配置，直接发送至用户指定的官方 API 端点、自定义代理地址或其他第三方服务地址。我们不作为中间人中转、拦截、读取或留存您的对话数据。
4. 用户应妥善保管自己的 API Key、账号、访问凭据及设备安全。因用户主动泄露、设备遗失、系统被入侵、第三方同步账号异常、配置不当或使用不可信代理服务导致的凭据泄露、数据丢失、费用损失或其他后果，由用户自行承担。
5. 用户应自行备份重要聊天记录、配置文件及相关数据。因设备故障、系统重装、软件卸载、误删除、云同步异常、第三方服务变化或其他非我们可控原因导致的数据丢失、损坏或无法恢复，我们不承担责任，但法律另有规定的除外。

六、知识产权

1. 本软件的界面设计、交互逻辑、代码、图标、名称、标识、文档及其他相关内容，除依法属于第三方或开源项目的部分外，其所有权及知识产权归我们或相应权利人所有。
2. 未经我们事先书面许可，用户不得对本软件进行反向工程、反向编译、反汇编、恶意修改、非法复制、再分发、出售、出租、转授权，或以其他方式侵犯本软件相关知识产权及合法权益，但法律法规明确允许的情形除外。
3. 本软件可能使用第三方开源库、框架或组件。相关开源项目的使用、复制、修改和分发，应遵守其各自适用的开源许可证。
4. 用户通过本软件调用第三方 AI 服务所生成内容的权利归属、使用限制及责任承担，由用户与相应第三方服务提供方依据其服务条款、内容政策及适用法律法规确定。我们不对 AI 生成内容是否享有版权、是否侵犯第三方权益、是否可商用或是否适合特定用途作出任何保证。

七、免责声明与责任限制

1. 本软件按“现状”和“可用”状态提供。在法律允许的范围内，我们不对本软件作出任何明示或暗示的担保，包括但不限于适销性、特定用途适用性、准确性、持续可用性、无错误、无中断或完全安全的担保。
2. 我们不保证本软件的功能一定能满足用户的全部需求，也不保证本软件在所有设备、系统版本、网络环境、地区政策、第三方 API 状态或应用商店规则下均能正常、持续或不间断运行。
3. 因第三方 AI 模型、第三方 API、第三方平台、自定义代理、中转服务、网络服务商、操作系统、应用商店政策或其他非我们可控因素导致的服务不可用、内容异常、数据延迟、费用损失、账号限制或其他后果，在法律允许的范围内，我们不承担责任。
4. 对于第三方 AI 模型独立生成的内容所引发的事实错误、法律风险、道德争议、版权争议、财产损失、名誉损害或其他纠纷，在法律允许的范围内，应由用户及相应第三方服务提供方根据其服务协议和适用法律自行承担责任。
5. 用户理解并同意，AI 生成内容可能存在不准确、不完整、不适当或误导性信息。用户在依据 AI 生成内容采取任何行动前，应结合自身判断，并在涉及医疗、法律、金融、安全、教育升学等重要事项时咨询具备资质的专业人士。
6. 在法律允许的范围内，我们因本协议或本软件所承担的累计赔偿责任，以用户为获得本软件使用权而实际向我们支付的费用总额为上限；如本软件为免费提供，则以人民币 100 元为上限。但因我们故意或重大过失造成用户人身损害、财产重大损失，或法律法规另有强制性规定的情形除外。

八、协议的修改、终止与争议解决

1. 我们有权根据法律法规变化、应用商店规则调整、软件功能变化、第三方服务变化或运营需要，对本协议进行必要修改。
2. 修改后的协议将在软件内或其他适当位置公布。对于涉及用户重大权益变化的内容，我们将尽合理努力通过软件内提示、更新说明或其他适当方式提醒用户。
3. 如用户不同意修改后的协议，可以停止使用并卸载本软件。用户在修改后的协议生效后继续使用本软件的，视为已接受修改后的协议。
4. 如用户违反本协议、适用法律法规或第三方服务规则，用户应自行承担因此产生的责任。我们有权在法律允许范围内采取必要措施保护本软件、其他用户及我们自身的合法权益。
5. 本协议的订立、执行、解释及争议解决，均适用中华人民共和国法律，不含港澳台地区法律及冲突法规则。
6. 如双方就本协议内容或其执行发生争议，双方应首先友好协商解决；协商不成的，任何一方均可向开发者住所地有管辖权的人民法院提起诉讼。

九、其他

1. 本协议部分条款被认定为无效、违法或不可执行的，不影响其他条款的效力。双方应在法律允许范围内，以最接近原条款目的的有效条款替代该无效、违法或不可执行条款。
2. 本协议标题仅为阅读方便而设，不影响协议条款的解释。
3. 本协议构成用户与我们之间关于本软件使用事项的完整协议，并取代双方此前就同一事项达成的任何口头或书面约定。

点击“同意并继续”，即表示您已充分阅读、理解并接受本协议的全部内容。
"""
}
