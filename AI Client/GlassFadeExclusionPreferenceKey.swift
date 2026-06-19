import Foundation
import SwiftUI

struct GlassFadeExclusionPreferenceKey: PreferenceKey {
    static var defaultValue: [GlassFadeExclusion] = []

    static func reduce(value: inout [GlassFadeExclusion], nextValue: () -> [GlassFadeExclusion]) {
        value.append(contentsOf: nextValue())
    }
}
