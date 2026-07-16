import SwiftUI

struct AIProviderKeyManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var configuration: AIConfiguration
    @State private var runtimeState: AIProviderKeyStateStore.State
    @State private var editor: KeyEditorDraft?
    @State private var keyPendingDeletion: AIProviderAPIKey?
    @State private var saveErrorMessage: String?

    private let stateStore: AIProviderKeyStateStore
    private let saveConfiguration: (AIConfiguration) -> Bool

    init(
        configuration: AIConfiguration,
        stateStore: AIProviderKeyStateStore = .shared,
        saveConfiguration: @escaping (AIConfiguration) -> Bool
    ) {
        self._configuration = State(initialValue: configuration)
        self._runtimeState = State(initialValue: stateStore.state(for: configuration.id))
        self.stateStore = stateStore
        self.saveConfiguration = saveConfiguration
    }

    private var currentKeyID: UUID? {
        if let currentKeyID = runtimeState.currentKeyID,
           configuration.apiKeys.contains(where: { $0.id == currentKeyID }) {
            return currentKeyID
        }
        return configuration.apiKeys.first?.id
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if configuration.apiKeys.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "key")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(AppLocalizations.string(
                                "providerKey.management.emptyTitle",
                                defaultValue: "No API Keys"
                            ))
                            .font(.headline)
                            Text(AppLocalizations.string(
                                "providerKey.management.emptyMessage",
                                defaultValue: "Add a key to use the provider's built-in authentication."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(configuration.apiKeys) { key in
                            keyRow(key)
                        }
                    }
                } header: {
                    Text(AppLocalizations.string(
                        "providerKey.management.keysSection",
                        defaultValue: "API Keys"
                    ))
                } footer: {
                    Text(AppLocalizations.string(
                        "providerKey.management.autoSwitch",
                        defaultValue: "The current key is tried first. Authentication failures and rate limits automatically switch to the next key."
                    ))
                }
            }
            .navigationTitle(AppLocalizations.string(
                "providerKey.management.title",
                defaultValue: "Manage API Keys"
            ))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalizations.string("providerKey.management.done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = KeyEditorDraft(key: nil)
                    } label: {
                        Label(
                            AppLocalizations.string(
                                "providerKey.management.add",
                                defaultValue: "Add API Key"
                            ),
                            systemImage: "plus"
                        )
                    }
                }
            }
            .sheet(item: $editor) { draft in
                AIProviderKeyEditor(
                    title: draft.key == nil
                        ? AppLocalizations.string("providerKey.management.add", defaultValue: "Add API Key")
                        : AppLocalizations.string("providerKey.management.edit", defaultValue: "Edit API Key"),
                    initialName: draft.key?.name
                        ?? AIConfiguration.defaultAPIKeyName(index: configuration.apiKeys.count + 1),
                    initialSecret: draft.key?.value ?? ""
                ) { name, secret in
                    saveKey(draft.key?.id, name: name, secret: secret)
                }
            }
            .confirmationDialog(
                AppLocalizations.string(
                    "providerKey.management.deleteConfirmationTitle",
                    defaultValue: "Delete API Key?"
                ),
                isPresented: Binding(
                    get: { keyPendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented {
                            keyPendingDeletion = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(
                    AppLocalizations.string("providerKey.management.deleteAction", defaultValue: "Delete"),
                    role: .destructive
                ) {
                    if let keyPendingDeletion {
                        deleteKey(keyPendingDeletion)
                    }
                }
                Button(AppLocalizations.string("providerKey.management.cancel", defaultValue: "Cancel"), role: .cancel) {}
            } message: {
                Text(AppLocalizations.string(
                    "providerKey.management.deleteConfirmationMessage",
                    defaultValue: "This key will be removed from this provider and deleted from Keychain."
                ))
            }
            .alert(
                AppLocalizations.string("providerKey.management.saveFailedTitle", defaultValue: "Couldn't Save Configuration"),
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            saveErrorMessage = nil
                        }
                    }
                )
            ) {
                Button(AppLocalizations.string("providerKey.management.ok", defaultValue: "OK"), role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyStateDidChange)) { notification in
                guard let changedConfigurationID = notification.userInfo?["configurationID"] as? UUID,
                      changedConfigurationID == configuration.id else {
                    return
                }
                refreshRuntimeState()
            }
        }
    }

    @ViewBuilder
    private func keyRow(_ key: AIProviderAPIKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    stateStore.setCurrentKeyID(key.id, for: configuration.id)
                    refreshRuntimeState()
                } label: {
                    Image(systemName: currentKeyID == key.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(currentKeyID == key.id ? Color.accentColor : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(currentKeyID == key.id
                    ? AppLocalizations.string("providerKey.management.current", defaultValue: "Current API Key")
                    : AppLocalizations.string("providerKey.management.makeCurrent", defaultValue: "Make Current API Key"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(key.name)
                        .foregroundStyle(.primary)
                    Text(key.maskedSuffix)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    editor = KeyEditorDraft(key: key)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(AppLocalizations.string(
                    "providerKey.management.edit",
                    defaultValue: "Edit API Key"
                ))

                Button(role: .destructive) {
                    keyPendingDeletion = key
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(AppLocalizations.string(
                    "providerKey.management.delete",
                    defaultValue: "Delete API Key"
                ))
            }

            if let failure = runtimeState.failures[key.id] {
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.category.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                    if let statusCode = failure.statusCode {
                        Text(AppLocalizations.format(
                            "providerKey.management.failureStatus",
                            defaultValue: "HTTP %d",
                            arguments: [statusCode]
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Text(failure.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text(failure.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button(AppLocalizations.string(
                        "providerKey.management.clearFailure",
                        defaultValue: "Clear Error"
                    )) {
                        stateStore.clearFailure(for: key.id, configurationID: configuration.id)
                        refreshRuntimeState()
                    }
                    .font(.caption)
                }
                .padding(.leading, 40)
            }
        }
        .padding(.vertical, 3)
    }

    private func saveKey(_ keyID: UUID?, name: String, secret: String) -> Bool {
        let wasEmptyBeforeAdding = configuration.apiKeys.isEmpty
        var updatedConfiguration = configuration
        do {
            if let keyID {
                try updatedConfiguration.updateAPIKey(id: keyID, name: name, value: secret)
            } else {
                try updatedConfiguration.addAPIKey(name: name, value: secret)
            }
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }

        guard persist(updatedConfiguration) else {
            refreshRuntimeState()
            return false
        }

        if let keyID {
            stateStore.clearFailure(for: keyID, configurationID: configuration.id)
        } else if wasEmptyBeforeAdding, let addedKeyID = updatedConfiguration.apiKeys.last?.id {
            stateStore.setCurrentKeyID(addedKeyID, for: configuration.id)
        }
        refreshRuntimeState()
        return true
    }

    private func deleteKey(_ key: AIProviderAPIKey) {
        let wasCurrentKey = currentKeyID == key.id
        let replacementKeyID = wasCurrentKey
            ? configuration.followingAPIKeyID(afterRemoving: key.id)
            : nil
        var updatedConfiguration = configuration
        guard updatedConfiguration.removeAPIKey(id: key.id) != nil else { return }
        guard persist(updatedConfiguration) else {
            refreshRuntimeState()
            return
        }

        if wasCurrentKey {
            stateStore.setCurrentKeyID(replacementKeyID, for: configuration.id)
        }
        refreshRuntimeState()
    }

    private func persist(_ updatedConfiguration: AIConfiguration) -> Bool {
        guard saveConfiguration(updatedConfiguration) else {
            saveErrorMessage = AppLocalizations.string(
                "configuration.saveFailed",
                defaultValue: "Failed to save configuration. Check Keychain or local storage permissions."
            )
            return false
        }

        configuration = updatedConfiguration
        refreshRuntimeState()
        return true
    }

    private func refreshRuntimeState() {
        runtimeState = stateStore.state(for: configuration.id)
    }

    private struct KeyEditorDraft: Identifiable {
        let id = UUID()
        let key: AIProviderAPIKey?
    }
}

private struct AIProviderKeyEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialName: String
    let initialSecret: String
    let onSave: (String, String) -> Bool

    @State private var name = ""
    @State private var secret = ""
    @State private var showsSecret = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        AppLocalizations.string("providerKey.editor.name", defaultValue: "Name"),
                        text: $name
                    )
                    .textInputAutocapitalization(.words)

                    if showsSecret {
                        TextField(
                            AppLocalizations.string("providerKey.editor.secret", defaultValue: "API Key"),
                            text: $secret
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    } else {
                        SecureField(
                            AppLocalizations.string("providerKey.editor.secret", defaultValue: "API Key"),
                            text: $secret
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }

                    Toggle(
                        AppLocalizations.string(
                            "providerKey.editor.showSecret",
                            defaultValue: "Show API Key"
                        ),
                        isOn: $showsSecret
                    )
                } footer: {
                    Text(AppLocalizations.string(
                        "providerKey.editor.footer",
                        defaultValue: "API keys are stored in Keychain and are never saved in the configuration file."
                    ))
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizations.string("providerKey.editor.cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizations.string("providerKey.editor.save", defaultValue: "Save")) {
                        if onSave(name, secret) {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                name = initialName
                secret = initialSecret
            }
        }
    }
}
