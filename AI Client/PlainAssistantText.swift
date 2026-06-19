import Foundation
import SwiftUI

struct PlainAssistantText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        SelectableTextView(
            text: content,
            textColor: .label,
            font: .preferredFont(forTextStyle: .body),
            textAlignment: .left
        )
    }
}
