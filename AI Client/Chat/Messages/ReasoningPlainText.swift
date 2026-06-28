import Foundation
import SwiftUI

struct ReasoningPlainText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        SelectableTextView(
            text: content,
            textColor: .secondaryLabel,
            font: .preferredFont(forTextStyle: .caption1),
            textAlignment: .left
        )
    }
}
