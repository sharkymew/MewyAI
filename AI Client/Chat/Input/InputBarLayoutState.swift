import CoreGraphics

struct InputBarLayoutState: Equatable {
    var measuredHeight: CGFloat = 0

    func effectiveHeight(fallback: CGFloat) -> CGFloat {
        max(measuredHeight, fallback)
    }

    func bottomContentPadding(fallback: CGFloat, gap: CGFloat) -> CGFloat {
        effectiveHeight(fallback: fallback) + gap
    }

    func scrollButtonBottomPadding(fallback: CGFloat, extraPadding: CGFloat = 12) -> CGFloat {
        effectiveHeight(fallback: fallback) + extraPadding
    }

    mutating func updateMeasuredHeight(_ height: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        guard abs(measuredHeight - height) > tolerance else { return false }
        measuredHeight = height
        return true
    }
}
