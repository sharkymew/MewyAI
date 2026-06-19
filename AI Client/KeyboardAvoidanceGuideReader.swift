import SwiftUI
import UIKit

struct KeyboardAvoidanceGuideReader: UIViewRepresentable {
    let onBottomPaddingChanged: (CGFloat) -> Void

    func makeUIView(context: Context) -> KeyboardAvoidanceGuideView {
        let view = KeyboardAvoidanceGuideView()
        view.onBottomPaddingChanged = onBottomPaddingChanged
        return view
    }

    func updateUIView(_ uiView: KeyboardAvoidanceGuideView, context: Context) {
        uiView.onBottomPaddingChanged = onBottomPaddingChanged
        uiView.publishCurrentPadding()
    }
}

final class KeyboardAvoidanceGuideView: UIView {
    var onBottomPaddingChanged: ((CGFloat) -> Void)?

    private let trackingView = UIView()
    private var lastPublishedPadding: CGFloat?
    private var didInstallConstraints = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        trackingView.isUserInteractionEnabled = false
        trackingView.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installConstraintsIfNeeded()
        publishCurrentPadding()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publishCurrentPadding()
    }

    func publishCurrentPadding() {
        installConstraintsIfNeeded()

        let overlap = max(trackingView.bounds.height, 0)
        let bottomSafeArea = window?.safeAreaInsets.bottom ?? safeAreaInsets.bottom
        let bottomPadding = max(overlap - bottomSafeArea, 0)
        guard abs((lastPublishedPadding ?? -.greatestFiniteMagnitude) - bottomPadding) > 0.5 else { return }

        lastPublishedPadding = bottomPadding
        DispatchQueue.main.async { [weak self] in
            self?.onBottomPaddingChanged?(bottomPadding)
        }
    }

    private func installConstraintsIfNeeded() {
        guard !didInstallConstraints else { return }
        didInstallConstraints = true

        trackingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackingView)

        NSLayoutConstraint.activate([
            trackingView.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
            trackingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
