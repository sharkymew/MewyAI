import Foundation
import JavaScriptCore
import Compression
import SwiftUI
import UIKit
import WebKit

nonisolated struct PreparedLaTeXFormula: @unchecked Sendable {
    let formula: String
    let displayMode: Bool
    let image: UIImage?
    let imageSize: CGSize
    let fallbackText: String
    let errorMessage: String?
    let allowsWebFallback: Bool

    var hasImage: Bool {
        image != nil && imageSize.width > 0 && imageSize.height > 0
    }
}

nonisolated enum LaTeXRenderBudget {
    static let maxFormulaCharacters = 2_000
    static let maxFormulasPerMessage = 64
    static let maxRenderedSVGCharacters = 400_000

    static func canRenderFormula(_ formula: String) -> Bool {
        formula.trimmingCharacters(in: .whitespacesAndNewlines).count <= maxFormulaCharacters
    }

    static func fallbackText(formula: String, displayMode: Bool) -> String {
        displayMode ? "\\[\(formula)\\]" : "\\(\(formula)\\)"
    }
}

struct PreparedLaTeXFormulaView: View {
    let formula: PreparedLaTeXFormula

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
    @State private var webHeight: CGFloat = 48

    var body: some View {
        Group {
            if let image = formula.image, formula.hasImage {
                ScrollView(.horizontal, showsIndicators: formula.displayMode) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: formula.imageSize.width, height: formula.imageSize.height)
                        .accessibilityLabel(Text(formula.formula))
                }
                .scrollDisabled(!formula.displayMode)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: formula.imageSize.height)
            } else if formula.allowsWebFallback,
                      LaTeXRenderBudget.canRenderFormula(formula.formula) {
                LaTeXFormulaWebView(
                    formula: formula.formula,
                    displayMode: formula.displayMode,
                    textColor: resolvedTextColor,
                    fontSize: fontSize,
                    height: $webHeight
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: webHeight)
            } else if formula.errorMessage != nil {
                LaTeXFallbackText(
                    text: formula.fallbackText,
                    fontSize: fontSize
                )
            } else {
                LaTeXFormulaWebView(
                    formula: formula.formula,
                    displayMode: formula.displayMode,
                    textColor: resolvedTextColor,
                    fontSize: fontSize,
                    height: $webHeight
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: webHeight)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var resolvedTextColor: String {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).cssHex
    }
}

struct LaTeXFormulaView: View, Equatable {
    let formula: String
    let displayMode: Bool

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
    @State private var webHeight: CGFloat = 48

    static func == (lhs: LaTeXFormulaView, rhs: LaTeXFormulaView) -> Bool {
        lhs.formula == rhs.formula && lhs.displayMode == rhs.displayMode
    }

    var body: some View {
        Group {
            if LaTeXRenderBudget.canRenderFormula(formula) {
                LaTeXFormulaWebView(
                    formula: formula,
                    displayMode: displayMode,
                    textColor: resolvedTextColor,
                    fontSize: fontSize,
                    height: $webHeight
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: webHeight)
            } else {
                LaTeXFallbackText(
                    text: LaTeXRenderBudget.fallbackText(formula: formula, displayMode: displayMode),
                    fontSize: fontSize
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var resolvedTextColor: String {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).cssHex
    }
}

struct LaTeXInlineTextView: View, Equatable {
    let text: String
    let textColor: UIColor
    let font: UIFont
    let textAlignment: NSTextAlignment

    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat

    init(
        text: String,
        textColor: UIColor,
        font: UIFont,
        textAlignment: NSTextAlignment
    ) {
        self.text = text
        self.textColor = textColor
        self.font = font
        self.textAlignment = textAlignment
        _height = State(initialValue: max(24, font.lineHeight + 6))
    }

    static func == (lhs: LaTeXInlineTextView, rhs: LaTeXInlineTextView) -> Bool {
        lhs.text == rhs.text
            && lhs.font.pointSize == rhs.font.pointSize
            && lhs.textAlignment == rhs.textAlignment
    }

    var body: some View {
        Group {
            if Self.canRenderInlineText(text) {
                LaTeXInlineTextWebView(
                    text: text,
                    textColor: resolvedTextColor,
                    fontSize: font.pointSize,
                    fontWeight: fontWeight,
                    fontStyle: fontStyle,
                    textAlignment: textAlignment.cssValue,
                    height: $height
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height)
            } else {
                Text(Self.attributedString(from: text))
                    .font(.system(size: font.pointSize))
                    .foregroundStyle(Color(textColor))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var resolvedTextColor: String {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return textColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).cssHex
    }

    private var fontWeight: String {
        font.fontDescriptor.symbolicTraits.contains(.traitBold) ? "700" : "400"
    }

    private var fontStyle: String {
        font.fontDescriptor.symbolicTraits.contains(.traitItalic) ? "italic" : "normal"
    }

    private static func canRenderInlineText(_ text: String) -> Bool {
        var formulaCount = 0
        for segment in ChatLaTeXSegmentParser.splitInlineMath(text) {
            guard case let .math(formula, _) = segment else { continue }
            formulaCount += 1
            guard formulaCount <= LaTeXRenderBudget.maxFormulasPerMessage,
                  LaTeXRenderBudget.canRenderFormula(formula) else {
                return false
            }
        }
        return true
    }

    private static func attributedString(from markdown: String) -> AttributedString {
        let inlineOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: markdown, options: inlineOptions)) ?? AttributedString(markdown)
    }
}

private struct LaTeXFallbackText: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: max(fontSize * 0.92, 12), design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LaTeXFormulaWebView: UIViewRepresentable {
    let formula: String
    let displayMode: Bool
    let textColor: String
    let fontSize: CGFloat
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        LaTeXWebViewSupport.makeWebView(coordinator: context.coordinator, scrollsHorizontally: displayMode)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height
        webView.scrollView.isScrollEnabled = displayMode
        webView.scrollView.showsHorizontalScrollIndicator = displayMode

        let signature = LaTeXFormulaHTML.signature(
            formula: formula,
            displayMode: displayMode,
            textColor: textColor,
            fontSize: fontSize
        )
        guard context.coordinator.signature != signature else { return }

        context.coordinator.signature = signature
        webView.loadHTMLString(
            LaTeXFormulaHTML.html(
                formula: formula,
                displayMode: displayMode,
                textColor: textColor,
                fontSize: fontSize
            ),
            baseURL: nil
        )
    }

    func makeCoordinator() -> LaTeXWebViewCoordinator {
        LaTeXWebViewCoordinator(height: $height)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: LaTeXWebViewCoordinator) {
        LaTeXWebViewSupport.dismantle(uiView)
    }
}

private struct LaTeXInlineTextWebView: UIViewRepresentable {
    let text: String
    let textColor: String
    let fontSize: CGFloat
    let fontWeight: String
    let fontStyle: String
    let textAlignment: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        LaTeXWebViewSupport.makeWebView(coordinator: context.coordinator, scrollsHorizontally: false)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height

        let signature = LaTeXInlineTextHTML.signature(
            text: text,
            textColor: textColor,
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            textAlignment: textAlignment
        )
        guard context.coordinator.signature != signature else { return }

        context.coordinator.signature = signature
        webView.loadHTMLString(
            LaTeXInlineTextHTML.html(
                text: text,
                textColor: textColor,
                fontSize: fontSize,
                fontWeight: fontWeight,
                fontStyle: fontStyle,
                textAlignment: textAlignment
            ),
            baseURL: nil
        )
    }

    func makeCoordinator() -> LaTeXWebViewCoordinator {
        LaTeXWebViewCoordinator(height: $height)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: LaTeXWebViewCoordinator) {
        LaTeXWebViewSupport.dismantle(uiView)
    }
}

private final class LaTeXWebViewCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var height: Binding<CGFloat>
    var signature = ""

    init(height: Binding<CGFloat>) {
        self.height = height
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == LaTeXWebViewSupport.messageName,
              let body = message.body as? [String: Any],
              let nextHeight = body["height"] as? Double else {
            return
        }

        let clampedHeight = min(max(CGFloat(nextHeight), 24), 720)
        if abs(height.wrappedValue - clampedHeight) > 0.5 {
            height.wrappedValue = clampedHeight
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        let isInitialDocumentLoad = navigationAction.navigationType == .other
            && (url == nil || url?.absoluteString == "about:blank")

        if isInitialDocumentLoad {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
}

private enum LaTeXWebViewSupport {
    static let messageName = "latexRender"
    static let scriptURLString = "\(resourceScheme)://bundle/mathjax-headless-svg.js"
    private static let resourceScheme = "aiclientmathjax"

    static func makeWebView(coordinator: LaTeXWebViewCoordinator, scrollsHorizontally: Bool) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: messageName)
        configuration.setURLSchemeHandler(LaTeXWebViewResourceHandler(), forURLScheme: resourceScheme)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.navigationDelegate = coordinator
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = scrollsHorizontally
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = scrollsHorizontally
        webView.scrollView.bounces = scrollsHorizontally
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    static func dismantle(_ webView: WKWebView) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        webView.navigationDelegate = nil
    }
}

private nonisolated enum MathJaxScriptLoader {
    private static let resourceName = "mathjax-headless-svg"
    private static let compressedExtension = "js.lzma"
    private static let initialBufferSize = 3_000_000
    private static let maxDecompressedBytes = 8_000_000

    private static let cachedScriptData: Result<Data, Error> = Result {
        guard let compressedScriptURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: compressedExtension
        ) else {
            throw ScriptLoadError.resourceMissing
        }

        let compressedData = try Data(contentsOf: compressedScriptURL)
        return try decompressedData(from: compressedData)
    }

    static func scriptData() throws -> Data {
        try cachedScriptData.get()
    }

    static func scriptString() throws -> String {
        let data = try scriptData()
        guard let script = String(data: data, encoding: .utf8) else {
            throw ScriptLoadError.invalidUTF8
        }
        return script
    }

    private static func decompressedData(from compressedData: Data) throws -> Data {
        var destinationSize = max(initialBufferSize, compressedData.count * 6)

        while destinationSize <= maxDecompressedBytes {
            var output = Data(count: destinationSize)
            let decodedCount = output.withUnsafeMutableBytes { destinationBuffer in
                compressedData.withUnsafeBytes { sourceBuffer -> Int in
                    guard let destination = destinationBuffer.baseAddress,
                          let source = sourceBuffer.baseAddress else {
                        return 0
                    }

                    return compression_decode_buffer(
                        destination.assumingMemoryBound(to: UInt8.self),
                        destinationSize,
                        source.assumingMemoryBound(to: UInt8.self),
                        compressedData.count,
                        nil,
                        COMPRESSION_LZMA
                    )
                }
            }

            if decodedCount > 0 {
                output.removeSubrange(decodedCount..<output.count)
                return output
            }

            destinationSize *= 2
        }

        throw ScriptLoadError.decompressionFailed
    }

    private enum ScriptLoadError: LocalizedError {
        case resourceMissing
        case decompressionFailed
        case invalidUTF8

        var errorDescription: String? {
            switch self {
            case .resourceMissing:
                return "mathjax-headless-svg.js.lzma missing from bundle"
            case .decompressionFailed:
                return "MathJax script decompression failed"
            case .invalidUTF8:
                return "MathJax script is not valid UTF-8"
            }
        }
    }
}

private final class LaTeXWebViewResourceHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              requestURL.lastPathComponent == "mathjax-headless-svg.js",
              let data = try? MathJaxScriptLoader.scriptData() else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: requestURL,
            mimeType: "application/javascript",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private enum LaTeXFormulaHTML {
    static func signature(
        formula: String,
        displayMode: Bool,
        textColor: String,
        fontSize: CGFloat
    ) -> String {
        "\(textColor):\(Int(fontSize * 10)):\(displayMode):\(formula.count):\(formula.hashValue)"
    }

    static func html(
        formula: String,
        displayMode: Bool,
        textColor: String,
        fontSize: CGFloat
    ) -> String {
        let encodedFormula = Data(formula.utf8).base64EncodedString()
        let escapedFormula = formula.htmlEscaped
        let displayLiteral = displayMode ? "true" : "false"
        let containerDisplay = displayMode ? "block" : "inline-block"
        let verticalPadding = displayMode ? "6px" : "0"

        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: \(textColor);
            font-size: \(fontSize)px;
            -webkit-text-size-adjust: 100%;
            overflow: hidden;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
        }
        #formula {
            box-sizing: border-box;
            width: 100%;
            min-height: 1px;
            padding: \(verticalPadding) 0;
            overflow-x: auto;
            overflow-y: hidden;
            -webkit-overflow-scrolling: touch;
        }
        mjx-container {
            margin: 0 !important;
            color: \(textColor);
            outline: 0;
        }
        mjx-container[jax="SVG"] {
            display: \(containerDisplay);
            text-align: left !important;
        }
        mjx-container[jax="SVG"] > svg {
            max-width: none;
        }
        .fallback {
            margin: 0;
            white-space: pre-wrap;
            overflow-wrap: anywhere;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-size: 0.94em;
            line-height: 1.35;
            color: \(textColor);
        }
        </style>
        <script src="\(LaTeXWebViewSupport.scriptURLString)"></script>
        </head>
        <body>
        <div id="formula"><pre class="fallback">\(escapedFormula)</pre></div>
        <script>
        const encodedFormula = "\(encodedFormula)";
        const displayMode = \(displayLiteral);
        \(sharedScript(targetSelector: "#formula"))
        renderFormulaElement(document.getElementById("formula"), encodedFormula, displayMode);
        window.setTimeout(reportHeight, 120);
        </script>
        </body>
        </html>
        """
    }

    static func sharedScript(targetSelector: String) -> String {
        """
        function decodeFormula(value) {
            const binary = atob(value);
            const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
            return new TextDecoder("utf-8").decode(bytes);
        }

        function reportHeight() {
            requestAnimationFrame(() => {
                const target = document.querySelector("\(targetSelector)") || document.body;
                const rect = target.getBoundingClientRect();
                const height = Math.ceil(Math.max(24, rect.height));
                window.webkit.messageHandlers.\(LaTeXWebViewSupport.messageName).postMessage({ height });
            });
        }

        function sanitizeRenderedSVG(svg) {
            const template = document.createElement("template");
            template.innerHTML = String(svg || "");
            template.content.querySelectorAll("script, foreignObject, iframe, object, embed, image, audio, video").forEach(element => element.remove());
            template.content.querySelectorAll("*").forEach(element => {
                for (const attribute of Array.from(element.attributes)) {
                    const name = attribute.name.toLowerCase();
                    const value = String(attribute.value || "");
                    const lowerValue = value.trim().toLowerCase();
                    if (name.startsWith("on")
                        || name === "href"
                        || name === "xlink:href"
                        || name === "src"
                        || ((name === "style" || name === "class") && /(url\\s*\\(|expression\\s*\\(|javascript:)/i.test(lowerValue))) {
                        element.removeAttribute(attribute.name);
                    }
                }
            });
            return template.innerHTML;
        }

        function renderFormulaElement(target, encoded, display) {
            if (!target || !window.AIClientMathJax || !AIClientMathJax.renderToSVG) {
                reportHeight();
                return;
            }
            try {
                const source = decodeFormula(encoded);
                const response = JSON.parse(AIClientMathJax.renderToSVG(source, display));
                if (response.ok && response.svg) {
                    target.innerHTML = sanitizeRenderedSVG(response.svg);
                }
            } catch (_) {}
            reportHeight();
        }
        """
    }
}

private enum LaTeXInlineTextHTML {
    static func signature(
        text: String,
        textColor: String,
        fontSize: CGFloat,
        fontWeight: String,
        fontStyle: String,
        textAlignment: String
    ) -> String {
        "\(textColor):\(Int(fontSize * 10)):\(fontWeight):\(fontStyle):\(textAlignment):\(text.count):\(text.hashValue)"
    }

    static func html(
        text: String,
        textColor: String,
        fontSize: CGFloat,
        fontWeight: String,
        fontStyle: String,
        textAlignment: String
    ) -> String {
        let content = inlineHTML(from: text)

        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: \(textColor);
            font-size: \(fontSize)px;
            -webkit-text-size-adjust: 100%;
            overflow: hidden;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
        }
        #content {
            box-sizing: border-box;
            width: 100%;
            min-height: 1px;
            line-height: 1.42;
            font-weight: \(fontWeight);
            font-style: \(fontStyle);
            text-align: \(textAlignment);
            overflow-wrap: anywhere;
        }
        mjx-container {
            color: \(textColor);
            outline: 0;
        }
        mjx-container[jax="SVG"] {
            display: inline-block;
            margin: 0 0.05em !important;
            vertical-align: -0.18em;
        }
        mjx-container[jax="SVG"] > svg {
            max-width: none;
        }
        .math-block {
            display: block;
            margin: 0.35em 0;
            overflow-x: auto;
            overflow-y: hidden;
        }
        code {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            background: rgba(120, 120, 128, 0.18);
            border-radius: 4px;
            padding: 0 0.22em;
        }
        </style>
        <script src="\(LaTeXWebViewSupport.scriptURLString)"></script>
        </head>
        <body>
        <div id="content">\(content)</div>
        <script>
        \(LaTeXFormulaHTML.sharedScript(targetSelector: "#content"))
        document.querySelectorAll("[data-formula]").forEach(element => {
            renderFormulaElement(element, element.dataset.formula, element.dataset.display === "true");
        });
        window.setTimeout(reportHeight, 120);
        </script>
        </body>
        </html>
        """
    }

    private static func inlineHTML(from text: String) -> String {
        var html = ""
        var state = InlineHTMLState()

        for segment in ChatLaTeXSegmentParser.splitInlineMath(text) {
            switch segment {
            case let .text(value):
                html += markdownHTML(from: value, state: &state)
            case let .math(formula, displayMode):
                if state.renderedFormulaCount < LaTeXRenderBudget.maxFormulasPerMessage,
                   LaTeXRenderBudget.canRenderFormula(formula) {
                    state.renderedFormulaCount += 1
                    html += mathHTML(formula: formula, displayMode: displayMode)
                } else {
                    html += LaTeXRenderBudget
                        .fallbackText(formula: formula, displayMode: displayMode)
                        .htmlEscaped
                }
            }
        }

        if state.isCode {
            html += "</code>"
        }
        if state.isBold {
            html += "</strong>"
        }
        return html
    }

    private struct InlineHTMLState {
        var isBold = false
        var isCode = false
        var renderedFormulaCount = 0
    }

    private static func mathHTML(formula: String, displayMode: Bool) -> String {
        let tag = displayMode ? "div" : "span"
        let className = displayMode ? "math-block" : "math-inline"
        let encoded = Data(formula.utf8).base64EncodedString()
        return "<\(tag) class=\"\(className)\" data-display=\"\(displayMode ? "true" : "false")\" data-formula=\"\(encoded)\">\(formula.htmlEscaped)</\(tag)>"
    }

    private static func markdownHTML(from text: String, state: inout InlineHTMLState) -> String {
        var html = ""
        var index = text.startIndex

        while index < text.endIndex {
            if !state.isCode && !isEscaped(index, in: text) {
                if text[index...].hasPrefix("**") {
                    html += toggleBold(state: &state)
                    index = text.index(index, offsetBy: 2)
                    continue
                }
                if text[index...].hasPrefix("__") {
                    html += toggleBold(state: &state)
                    index = text.index(index, offsetBy: 2)
                    continue
                }
            }

            if text[index] == "`", !isEscaped(index, in: text) {
                html += state.isCode ? "</code>" : "<code>"
                state.isCode.toggle()
                index = text.index(after: index)
                continue
            }

            if text[index] == "\n" {
                html += "<br>"
            } else {
                html += String(text[index]).htmlEscaped
            }
            index = text.index(after: index)
        }

        return html
    }

    private static func toggleBold(state: inout InlineHTMLState) -> String {
        let tag = state.isBold ? "</strong>" : "<strong>"
        state.isBold.toggle()
        return tag
    }

    private static func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var cursor = index
        var backslashCount = 0

        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            guard text[cursor] == "\\" else {
                break
            }
            backslashCount += 1
        }

        return backslashCount % 2 == 1
    }
}

nonisolated enum LaTeXInlineAttributedRenderer {
    static func attributedString(
        from text: String,
        font: UIFont,
        textColor: UIColor,
        textAlignment: NSTextAlignment,
        renderStyle: MarkdownRenderStyle
    ) async -> NSAttributedString {
        guard ChatLaTeXSegmentParser.containsInlineMath(in: text) else {
            return MarkdownInlineFormatter.attributedString(
                from: text,
                font: font,
                textColor: textColor,
                textAlignment: textAlignment
            )
        }

        let result = NSMutableAttributedString()
        var renderedFormulaCount = 0
        for segment in ChatLaTeXSegmentParser.splitInlineMath(text) {
            switch segment {
            case let .text(value):
                result.append(MarkdownInlineFormatter.attributedString(
                    from: value,
                    font: font,
                    textColor: textColor,
                    textAlignment: textAlignment
                ))
            case let .math(formula, displayMode):
                let formulaStyle = MarkdownRenderStyle(
                    textColor: textColor,
                    baseFont: font,
                    textAlignment: textAlignment,
                    userInterfaceStyle: renderStyle.userInterfaceStyle,
                    displayScale: renderStyle.displayScale
                )
                let prepared: PreparedLaTeXFormula
                if renderedFormulaCount < LaTeXRenderBudget.maxFormulasPerMessage,
                   LaTeXRenderBudget.canRenderFormula(formula) {
                    renderedFormulaCount += 1
                    prepared = await LaTeXSVGRenderer.shared.render(
                        formula: formula,
                        displayMode: displayMode,
                        style: formulaStyle
                    )
                } else {
                    prepared = LaTeXSVGRenderer.fallbackFormula(
                        formula: formula,
                        displayMode: displayMode,
                        error: "Formula render budget exceeded"
                    )
                }
                result.append(attachmentString(for: prepared, font: font, textColor: textColor))
            }
        }

        result.addAttributes(
            baseAttributes(font: font, textColor: textColor, textAlignment: textAlignment),
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private static func attachmentString(
        for formula: PreparedLaTeXFormula,
        font: UIFont,
        textColor: UIColor
    ) -> NSAttributedString {
        guard let image = formula.image, formula.hasImage else {
            return NSAttributedString(
                string: formula.fallbackText,
                attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: .regular),
                    .foregroundColor: textColor
                ]
            )
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        let baselineOffset = (font.capHeight - formula.imageSize.height) / 2
        attachment.bounds = CGRect(
            x: 0,
            y: baselineOffset,
            width: formula.imageSize.width,
            height: formula.imageSize.height
        )
        return NSAttributedString(attachment: attachment)
    }

    private static func baseAttributes(
        font: UIFont,
        textColor: UIColor,
        textAlignment: NSTextAlignment
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineSpacing = 3
        return [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
    }
}

actor LaTeXSVGRenderer {
    static let shared = LaTeXSVGRenderer()
    private static let imageRenderingEnabled = true

    private var context: JSContext?
    private var rendererFunction: JSValue?
    private var loadFailure: String?

    func render(
        formula: String,
        displayMode: Bool,
        style: MarkdownRenderStyle
    ) async -> PreparedLaTeXFormula {
        let trimmedFormula = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFormula.isEmpty else {
            return Self.fallback(formula: formula, displayMode: displayMode, error: "Empty formula")
        }

        guard LaTeXRenderBudget.canRenderFormula(trimmedFormula) else {
            return Self.fallback(
                formula: trimmedFormula,
                displayMode: displayMode,
                error: "Formula render budget exceeded"
            )
        }

        guard Self.imageRenderingEnabled else {
            return Self.fallback(
                formula: trimmedFormula,
                displayMode: displayMode,
                error: "Formula image rendering disabled"
            )
        }

        guard let rendererFunction = loadRendererFunction() else {
            return Self.fallback(
                formula: trimmedFormula,
                displayMode: displayMode,
                error: loadFailure ?? "MathJax renderer unavailable",
                allowsWebFallback: true
            )
        }

        guard !Task.isCancelled else {
            return Self.fallback(
                formula: trimmedFormula,
                displayMode: displayMode,
                error: "Render cancelled",
                allowsWebFallback: true
            )
        }

        guard let rawResult = rendererFunction.call(withArguments: [trimmedFormula, displayMode])?.toString(),
              let response = Self.decodeResponse(rawResult),
              response.ok,
              let rawSVG = response.svg else {
            let error = context?.exception?.toString() ?? "MathJax conversion failed"
            return Self.fallback(
                formula: trimmedFormula,
                displayMode: displayMode,
                error: error,
                allowsWebFallback: true
            )
        }

        guard rawSVG.count <= LaTeXRenderBudget.maxRenderedSVGCharacters else {
            return Self.fallback(
                formula: trimmedFormula,
                displayMode: displayMode,
                error: "Rendered SVG exceeded budget"
            )
        }

        guard let renderedImage = Self.renderedImage(
            from: rawSVG,
            textColor: style.resolvedTextColor,
            fontSize: style.baseFont.pointSize,
            displayScale: style.displayScale
        ) else {
            return Self.fallback(
                formula: trimmedFormula,
                displayMode: displayMode,
                error: "SVG image decoding failed",
                allowsWebFallback: true
            )
        }

        return PreparedLaTeXFormula(
            formula: trimmedFormula,
            displayMode: displayMode,
            image: renderedImage.image,
            imageSize: renderedImage.size,
            fallbackText: Self.fallbackText(formula: trimmedFormula, displayMode: displayMode),
            errorMessage: nil,
            allowsWebFallback: false
        )
    }

    nonisolated static func fallbackFormula(
        formula: String,
        displayMode: Bool,
        error: String
    ) -> PreparedLaTeXFormula {
        fallback(formula: formula, displayMode: displayMode, error: error)
    }

    private func loadRendererFunction() -> JSValue? {
        if let rendererFunction { return rendererFunction }
        if loadFailure != nil { return nil }

        do {
            let script = try MathJaxScriptLoader.scriptString()
            let nextContext = JSContext()
            nextContext?.evaluateScript(script)
            if let exception = nextContext?.exception?.toString() {
                loadFailure = exception
                return nil
            }
            guard let renderer = nextContext?
                .objectForKeyedSubscript("AIClientMathJax")?
                .objectForKeyedSubscript("renderToSVG"),
                  !renderer.isUndefined else {
                loadFailure = "AIClientMathJax.renderToSVG missing"
                return nil
            }
            context = nextContext
            rendererFunction = renderer
            return renderer
        } catch {
            loadFailure = error.localizedDescription
            return nil
        }
    }

    private static func decodeResponse(_ rawResult: String) -> MathJaxRenderResponse? {
        guard let data = rawResult.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MathJaxRenderResponse.self, from: data)
    }

    private static func renderedImage(
        from rawSVG: String,
        textColor: UIColor,
        fontSize: CGFloat,
        displayScale: CGFloat
    ) -> (image: UIImage, size: CGSize)? {
        guard var svg = extractSVG(from: rawSVG) else { return nil }
        let size = size(from: svg, fontSize: fontSize)
        guard size.width > 0, size.height > 0 else { return nil }

        svg = sanitizedSVG(svg)
        svg = svg.replacingOccurrences(of: "currentColor", with: textColor.cssHex)
        svg = replaceAttribute("width", with: Self.svgNumber(size.width), in: svg)
        svg = replaceAttribute("height", with: Self.svgNumber(size.height), in: svg)

        guard let data = svg.data(using: .utf8),
              let sourceImage = UIImage(data: data, scale: max(displayScale, 1)) else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(displayScale, 1)
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: size))
        }
        return (image, size)
    }

    private static func extractSVG(from rawSVG: String) -> String? {
        guard let start = rawSVG.range(of: "<svg"),
              let end = rawSVG.range(of: "</svg>", options: .backwards) else {
            return nil
        }
        return String(rawSVG[start.lowerBound..<end.upperBound])
    }

    private static func sanitizedSVG(_ svg: String) -> String {
        var result = svg
        let patterns = [
            #"<script\b[^>]*>[\s\S]*?</script>"#,
            #"<foreignObject\b[^>]*>[\s\S]*?</foreignObject>"#,
            #"<(?:iframe|object|embed|image|audio|video)\b[^>]*/?>"#,
            #"\s+on[a-zA-Z]+\s*=\s*"[^"]*""#,
            #"\s+(?:xlink:)?href\s*=\s*"[^"]*""#,
            #"\s+src\s*=\s*"[^"]*""#,
            #"\s+style\s*=\s*"[^"]*(?:url\s*\(|expression\s*\(|javascript:)[^"]*""#
        ]

        for pattern in patterns {
            result = replacingSVG(pattern: pattern, in: result, template: "")
        }
        return result
    }

    private static func replacingSVG(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func size(from svg: String, fontSize: CGFloat) -> CGSize {
        let width = length(attribute: "width", in: svg, fontSize: fontSize)
        let height = length(attribute: "height", in: svg, fontSize: fontSize)
        if width > 0, height > 0 {
            return CGSize(width: ceil(width), height: ceil(height))
        }

        guard let viewBox = attribute("viewBox", in: svg) else { return .zero }
        let values = viewBox
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        guard values.count == 4, values[2] > 0, values[3] > 0 else { return .zero }
        return CGSize(
            width: ceil(CGFloat(values[2]) * fontSize / 1_000),
            height: ceil(CGFloat(values[3]) * fontSize / 1_000)
        )
    }

    private static func length(attribute name: String, in svg: String, fontSize: CGFloat) -> CGFloat {
        guard let value = attribute(name, in: svg) else { return 0 }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = CGFloat(Double(trimmed.prefix { $0.isNumber || $0 == "." || $0 == "-" }) ?? 0)
        if trimmed.hasSuffix("ex") {
            return number * fontSize * 0.431
        }
        if trimmed.hasSuffix("em") {
            return number * fontSize
        }
        return number
    }

    private static func attribute(_ name: String, in svg: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(^|\s)\#(name)="([^"]+)""#) else { return nil }
        let range = NSRange(svg.startIndex..<svg.endIndex, in: svg)
        guard let match = regex.firstMatch(in: svg, range: range),
              let valueRange = Range(match.range(at: 2), in: svg) else {
            return nil
        }
        return String(svg[valueRange])
    }

    private static func replaceAttribute(_ name: String, with value: String, in svg: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(^|\s)\#(name)="[^"]+""#) else { return svg }
        let range = NSRange(svg.startIndex..<svg.endIndex, in: svg)
        return regex.stringByReplacingMatches(
            in: svg,
            range: range,
            withTemplate: "$1\(name)=\"\(value)\""
        )
    }

    private static func fallback(
        formula: String,
        displayMode: Bool,
        error: String,
        allowsWebFallback: Bool = false
    ) -> PreparedLaTeXFormula {
        PreparedLaTeXFormula(
            formula: formula,
            displayMode: displayMode,
            image: nil,
            imageSize: .zero,
            fallbackText: fallbackText(formula: formula, displayMode: displayMode),
            errorMessage: error,
            allowsWebFallback: allowsWebFallback
        )
    }

    private static func fallbackText(formula: String, displayMode: Bool) -> String {
        LaTeXRenderBudget.fallbackText(formula: formula, displayMode: displayMode)
    }

    private static func svgNumber(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }
}

private nonisolated struct MathJaxRenderResponse: Decodable {
    let ok: Bool
    let svg: String?
    let error: String?
}

private nonisolated extension ColorScheme {
    var userInterfaceStyle: UIUserInterfaceStyle {
        self == .dark ? .dark : .light
    }
}

private extension NSTextAlignment {
    var cssValue: String {
        switch self {
        case .center:
            return "center"
        case .right:
            return "right"
        case .justified:
            return "justify"
        default:
            return "left"
        }
    }
}

private nonisolated extension UIColor {
    var cssHex: String {
        let color = resolvedColor(with: UITraitCollection.current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#1C1C1E"
        }

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}

private extension String {
    var htmlEscaped: String {
        var result = self
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }
}
