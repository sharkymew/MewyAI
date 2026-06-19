import Foundation
import SwiftUI

struct CollapsibleErrorMessageView: View {
    let message: String

    var body: some View {
        if let error = ErrorDetailContent.parse(message) {
            CollapsibleErrorDetailsView(error: error)
        } else {
            Text(message)
        }
    }
}
