import SwiftUI
import UIKit

struct CameraCaptureViewController: UIViewControllerRepresentable {
    let onCaptured: @MainActor @Sendable (UIImage) -> Void
    let onCancel: @MainActor @Sendable () -> Void

    @MainActor
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.showsCameraControls = true
        picker.delegate = context.coordinator

        if UIImagePickerController.isCameraDeviceAvailable(.rear) {
            picker.cameraDevice = .rear
        } else if UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptured: onCaptured, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCaptured: @MainActor @Sendable (UIImage) -> Void
        private let onCancel: @MainActor @Sendable () -> Void

        init(
            onCaptured: @escaping @MainActor @Sendable (UIImage) -> Void,
            onCancel: @escaping @MainActor @Sendable () -> Void
        ) {
            self.onCaptured = onCaptured
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                Task { @MainActor in onCancel() }
                return
            }

            Task { @MainActor in onCaptured(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in onCancel() }
        }
    }
}
