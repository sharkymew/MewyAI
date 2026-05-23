import SwiftUI
import UIKit
import WebKit

struct LaTeXFormulaView: View, Equatable {
    let formula: String
    let displayMode: Bool

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
    @State private var height: CGFloat

    init(formula: String, displayMode: Bool) {
        self.formula = formula
        self.displayMode = displayMode
        _height = State(initialValue: displayMode ? 48 : 28)
    }

    static func == (lhs: LaTeXFormulaView, rhs: LaTeXFormulaView) -> Bool {
        lhs.formula == rhs.formula && lhs.displayMode == rhs.displayMode
    }

    var body: some View {
        LaTeXFormulaWebView(
            formula: formula,
            displayMode: displayMode,
            textColor: textColor,
            fontSize: fontSize,
            height: $height
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .fixedSize(horizontal: false, vertical: true)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var textColor: String {
        colorScheme == .dark ? "#F2F2F7" : "#1C1C1E"
    }
}

private struct LaTeXFormulaWebView: UIViewRepresentable {
    let formula: String
    let displayMode: Bool
    let textColor: String
    let fontSize: CGFloat
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: LaTeXWebViewSupport.messageName)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = displayMode
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = displayMode
        webView.scrollView.bounces = displayMode
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
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
            baseURL: LaTeXWebViewSupport.baseURL
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: LaTeXWebViewSupport.messageName
        )
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
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
            switch navigationAction.navigationType {
            case .other:
                decisionHandler(.allow)
            default:
                decisionHandler(.cancel)
            }
        }
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
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: LaTeXWebViewSupport.messageName)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
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
            baseURL: LaTeXWebViewSupport.baseURL
        )
    }

    func makeCoordinator() -> LaTeXWebViewCoordinator {
        LaTeXWebViewCoordinator(height: $height)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: LaTeXWebViewCoordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: LaTeXWebViewSupport.messageName
        )
        uiView.navigationDelegate = nil
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
        switch navigationAction.navigationType {
        case .other:
            decisionHandler(.allow)
        default:
            decisionHandler(.cancel)
        }
    }
}

private enum LaTeXFormulaHTML {
    static func signature(
        formula: String,
        displayMode: Bool,
        textColor: String,
        fontSize: CGFloat
    ) -> String {
        "\(displayMode):\(textColor):\(Int(fontSize * 10)):\(formula.count):\(formula.hashValue)"
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
        let verticalPadding = displayMode ? "6px" : "0"
        let containerDisplay = displayMode ? "block" : "inline-block"

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
        mjx-assistive-mml {
            position: absolute !important;
            top: 0;
            left: 0;
            clip: rect(1px, 1px, 1px, 1px);
            padding: 1px 0 0 0 !important;
            border: 0 !important;
            height: 1px !important;
            width: 1px !important;
            overflow: hidden !important;
            display: block !important;
            user-select: none;
            pointer-events: none;
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
        <script>
        window.MathJax = {
            startup: { typeset: false },
            options: {
                enableMenu: false,
                enableAssistiveMml: false,
                renderActions: { addMenu: [] }
            },
            tex: {
                processEscapes: true,
                processEnvironments: true,
                tags: "ams"
            },
            svg: {
                fontCache: "none"
            }
        };
        </script>
        <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg-full.js"></script>
        </head>
        <body>
        <div id="formula"><pre class="fallback">\(escapedFormula)</pre></div>
        <script>
        const encodedFormula = "\(encodedFormula)";
        const displayMode = \(displayLiteral);
        var didRender = false;
        let renderPoll = window.setInterval(renderFormulaIfReady, 40);

        function decodeFormula(value) {
            const bytes = Uint8Array.from(atob(value), character => character.charCodeAt(0));
            return new TextDecoder("utf-8").decode(bytes);
        }

        function reportHeight() {
            requestAnimationFrame(() => {
                const formula = document.getElementById("formula");
                const math = formula ? formula.querySelector("mjx-container") : null;
                const target = math || formula || document.body;
                const rect = target.getBoundingClientRect();
                const style = formula ? window.getComputedStyle(formula) : null;
                const padding = math && style
                    ? parseFloat(style.paddingTop || "0") + parseFloat(style.paddingBottom || "0")
                    : 0;
                const height = Math.ceil(Math.max(
                    24,
                    rect.height + padding
                ));
                window.webkit.messageHandlers.\(LaTeXWebViewSupport.messageName).postMessage({ height });
            });
        }

        function showFallback() {
            window.clearInterval(renderPoll);
            didRender = true;
            reportHeight();
        }

        function renderFormulaIfReady() {
            if (didRender) { return; }
            if (!window.MathJax || !MathJax.tex2svgPromise) {
                return;
            }
            window.clearInterval(renderPoll);

            const source = decodeFormula(encodedFormula);
            MathJax.tex2svgPromise(source, { display: displayMode }).then(node => {
                const target = document.getElementById("formula");
                target.innerHTML = "";
                target.appendChild(node);
                didRender = true;
                reportHeight();
            }).catch(() => {
                showFallback();
            });
        }

        reportHeight();
        if (window.MathJax && MathJax.startup && MathJax.startup.promise) {
            MathJax.startup.promise.then(renderFormulaIfReady).catch(showFallback);
        } else {
            window.addEventListener("load", renderFormulaIfReady);
        }
        window.setTimeout(showFallback, 8000);
        </script>
        </body>
        </html>
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
        mjx-assistive-mml {
            position: absolute !important;
            top: 0;
            left: 0;
            clip: rect(1px, 1px, 1px, 1px);
            padding: 1px 0 0 0 !important;
            border: 0 !important;
            height: 1px !important;
            width: 1px !important;
            overflow: hidden !important;
            display: block !important;
            user-select: none;
            pointer-events: none;
        }
        code {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            background: rgba(120, 120, 128, 0.18);
            border-radius: 4px;
            padding: 0 0.22em;
        }
        </style>
        <script>
        window.MathJax = {
            startup: { typeset: false },
            options: {
                enableMenu: false,
                enableAssistiveMml: false,
                renderActions: { addMenu: [] }
            },
            tex: {
                inlineMath: [["\\\\(", "\\\\)"], ["$", "$"]],
                displayMath: [["\\\\[", "\\\\]"], ["$$", "$$"]],
                processEscapes: true,
                processEnvironments: true,
                tags: "ams"
            },
            svg: {
                fontCache: "none"
            }
        };
        </script>
        <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg-full.js"></script>
        </head>
        <body>
        <div id="content">\(content)</div>
        <script>
        const content = document.getElementById("content");
        var didRender = false;
        let renderPoll = window.setInterval(renderTextIfReady, 40);

        function reportHeight() {
            requestAnimationFrame(() => {
                const rect = content.getBoundingClientRect();
                const height = Math.ceil(Math.max(24, rect.height));
                window.webkit.messageHandlers.\(LaTeXWebViewSupport.messageName).postMessage({ height });
            });
        }

        function finishWithoutMathJax() {
            window.clearInterval(renderPoll);
            didRender = true;
            reportHeight();
        }

        function renderTextIfReady() {
            if (didRender) { return; }
            if (!window.MathJax || !MathJax.typesetPromise) {
                return;
            }
            window.clearInterval(renderPoll);

            MathJax.typesetPromise([content]).then(() => {
                didRender = true;
                reportHeight();
            }).catch(() => {
                finishWithoutMathJax();
            });
        }

        reportHeight();
        if (window.MathJax && MathJax.startup && MathJax.startup.promise) {
            MathJax.startup.promise.then(renderTextIfReady).catch(finishWithoutMathJax);
        } else {
            window.addEventListener("load", renderTextIfReady);
        }
        window.setTimeout(finishWithoutMathJax, 8000);
        </script>
        </body>
        </html>
        """
    }

    private static func inlineHTML(from text: String) -> String {
        var html = text.htmlEscaped
        html = replace(pattern: #"(?<!\\)\*\*(.+?)(?<!\\)\*\*"#, in: html, template: "<strong>$1</strong>")
        html = replace(pattern: #"(?<!\\)__(.+?)(?<!\\)__"#, in: html, template: "<strong>$1</strong>")
        html = replace(pattern: #"(?<!\\)`([^`\n]+)(?<!\\)`"#, in: html, template: "<code>$1</code>")
        html = html.replacingOccurrences(of: "\n", with: "<br>")
        return html
    }

    private static func replace(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

private enum LaTeXWebViewSupport {
    static let messageName = "latexRender"
    static let baseURL = URL(string: "https://cdn.jsdelivr.net/")!
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

private extension UIColor {
    var cssHex: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
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
