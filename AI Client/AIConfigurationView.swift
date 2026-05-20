import SwiftUI

struct AIConfigurationView: View {
    @AppStorage("baseURL") private var baseURL = "https://api.deepseek.com/chat/completions"
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("customHeaders") private var customHeaders = ""
    
    @Environment(\.dismiss) private var dismiss
    @State private var showAPIKey = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("请求地址")
                }
                
                Section {
                    if showAPIKey {
                        TextField("API Key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    Toggle("显示 API Key", isOn: $showAPIKey)
                } header: {
                    Text("认证")
                } footer: {
                    Text("填写 API Key 时会自动发送 Authorization: Bearer <API Key>。如果服务商使用其他认证方式，可以留空并在自定义请求头中配置。")
                }
                
                Section {
                    TextEditor(text: $customHeaders)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("自定义请求头")
                } footer: {
                    Text("每行一个请求头，格式为 Header-Name: value。自定义请求头会覆盖同名默认请求头。")
                }
            }
            .navigationTitle("AI 配置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AIConfigurationView()
}
