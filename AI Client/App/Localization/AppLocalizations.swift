import Foundation

nonisolated enum AppLocalizations {
    static func string(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        comment: StaticString = ""
    ) -> String {
        String(localized: key, defaultValue: defaultValue, comment: comment)
    }

    static func format(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        arguments: [CVarArg],
        comment: StaticString = ""
    ) -> String {
        String(
            format: string(key, defaultValue: defaultValue, comment: comment),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
