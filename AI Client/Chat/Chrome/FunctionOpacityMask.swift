import Foundation
import SwiftUI
import UIKit

struct FunctionOpacityMask: View {
    let topOpacity: Double
    let maxOpacity: Double
    let fadeInEnd: Double
    let holdEnd: Double
    let fadeOutEnd: Double
    var progressStartOffset: CGFloat = 0
    var progressLength: CGFloat?

    var body: some View {
        Canvas { context, size in
            let scale = max(UIScreen.main.scale, 1)
            let rowHeight = 1 / scale
            let rowCount = max(Int(ceil(size.height / rowHeight)), 1)

            for row in 0..<rowCount {
                let y = min(CGFloat(row) * rowHeight, size.height)
                let nextY = min(y + rowHeight, size.height)
                guard nextY > y else { continue }

                let midpoint = (y + nextY) * 0.5
                let length = max(progressLength ?? size.height, 1)
                let progress = Double((midpoint - progressStartOffset) / length)
                let opacity = opacity(at: progress)
                guard opacity > 0.001 else { continue }

                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: nextY - y)),
                    with: .color(.black.opacity(opacity))
                )
            }
        }
    }

    private func opacity(at rawProgress: Double) -> Double {
        let progress = min(max(rawProgress, 0), 1)

        if progress <= fadeInEnd {
            let phase = smootherStep(progress / fadeInEnd)
            return topOpacity + (maxOpacity - topOpacity) * phase
        }

        if progress <= holdEnd {
            return maxOpacity
        }

        if progress <= fadeOutEnd {
            let phase = smootherStep((progress - holdEnd) / (fadeOutEnd - holdEnd))
            return maxOpacity * (1 - phase)
        }

        return 0
    }

    private func smootherStep(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
