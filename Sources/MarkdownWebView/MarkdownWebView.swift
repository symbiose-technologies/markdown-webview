import SwiftUI
import WebKit

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#elseif os(iOS)
typealias PlatformViewRepresentable = UIViewRepresentable
#endif




@available(macOS 11.0, iOS 14.0, *)
public struct MarkdownWebView: PlatformViewRepresentable {
    public enum Error: Swift.Error {
        case invalidDefaultStylesheet
        case invalidLibScript
    }
    
    public enum StyleSheetType: Equatable, Codable, Hashable {
        case lib(DefaultStyle)
        case custom(css: String)
        
        public func getCssValue() throws -> String {
            switch self {
            case .custom(let css):
                return css
            case .lib(let defaultStyle):
                guard let defaultStylesheetFileURL = Bundle.module.url(forResource: defaultStyle.styleSheetName, withExtension: ""),
                      let defaultStylesheet = try? String(contentsOf: defaultStylesheetFileURL) else {
                    throw Error.invalidDefaultStylesheet
                }
                return defaultStylesheet
            }
            
            
            
        }
        
    }
    
    public enum DefaultStyle: Equatable, Codable, Hashable {
        case standard
        case messaging
        public var styleSheetName: String {
            #if os(macOS)
            switch self {
            case .standard:
                return "default-macOS"
            case .messaging:
                return "messaging-macOS"
            }
            #else
            switch self {
            case .standard:
                return "default-iOS"
            case .messaging:
                return "messaging-iOS"
                
            }
            #endif
        }
    }
    
    public struct CacheIdentity: Equatable, Codable, Hashable {
        public var markdownContent: String
        public var cssStyle: StyleSheetType
        public init(markdownContent: String, cssStyle: StyleSheetType) {
            self.markdownContent = markdownContent
            self.cssStyle = cssStyle
        }
    }
    
    
    let markdownContent: String
    let customStylesheet: String?
    let linkActivationHandler: ((URL) -> Void)?
    let renderedContentHandler: ((String) -> Void)?
    
    let defaultStyle: DefaultStyle
    
    
    public init(_ markdownContent: String, customStylesheet: String? = nil, defaultStyle: DefaultStyle = .standard) {
        self.markdownContent = markdownContent
        self.customStylesheet = customStylesheet
        self.defaultStyle = defaultStyle
        
        self.linkActivationHandler = nil
        self.renderedContentHandler = nil
    }
    
    internal init(_ markdownContent: String, customStylesheet: String?,
                  defaultStyle: DefaultStyle = .standard,
                  linkActivationHandler: ((URL) -> Void)?, renderedContentHandler: ((String) -> Void)?) {
        self.markdownContent = markdownContent
        self.customStylesheet = customStylesheet
        self.linkActivationHandler = linkActivationHandler
        self.renderedContentHandler = renderedContentHandler
        self.defaultStyle = defaultStyle
    }
    
    public func makeCoordinator() -> Coordinator { .init(parent: self) }
    
    #if os(macOS)
    public func makeNSView(context: Context) -> CustomWebView { context.coordinator.platformView }
    #elseif os(iOS)
    public func makeUIView(context: Context) -> CustomWebView { context.coordinator.platformView }
    #endif
    
    func updatePlatformView(_ platformView: CustomWebView, context: Context) {
        guard !platformView.isLoading else { return } /// This function might be called when the page is still loading, at which time `window.proxy` is not available yet.
        platformView.updateMarkdownContent(self.markdownContent)
    }
    
    #if os(macOS)
    public func updateNSView(_ nsView: CustomWebView, context: Context) { self.updatePlatformView(nsView, context: context) }
    #elseif os(iOS)
    public func updateUIView(_ uiView: CustomWebView, context: Context) { self.updatePlatformView(uiView, context: context) }
    #endif
    
        
    #if os(iOS)
    public func dismantleUIView(_ uiView: CustomWebView, coordinator: Coordinator) {
        WebViewPool.shared.returnWebView(uiView)
    }
    #elseif os(macOS)
    public func dismantleNSView(_ nsView: CustomWebView, coordinator: Coordinator) {
        WebViewPool.shared.returnWebView(nsView)
    }
    #endif
    
    
    public func onLinkActivation(_ linkActivationHandler: @escaping (URL) -> Void) -> Self {
        .init(self.markdownContent, 
              customStylesheet: self.customStylesheet,
              defaultStyle: self.defaultStyle, 
              linkActivationHandler: linkActivationHandler, renderedContentHandler: self.renderedContentHandler)
    }
    
    public func onRendered(_ renderedContentHandler: @escaping (String) -> Void) -> Self {
        .init(self.markdownContent, 
              customStylesheet: self.customStylesheet,
              defaultStyle: self.defaultStyle,
              linkActivationHandler: self.linkActivationHandler, renderedContentHandler: renderedContentHandler)
    }
    
    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: MarkdownWebView
        let platformView: CustomWebView
        let cssType: StyleSheetType
        
        init(parent: MarkdownWebView) {
            self.parent = parent
            self.platformView = WebViewPool.shared.getWebView()
//            self.platformView = .init()
            self.cssType = self.parent.customStylesheet != nil ? .custom(css: self.parent.customStylesheet!) : .lib(self.parent.defaultStyle)

            super.init()
            
            self.platformView.navigationDelegate = self
//            
            
            let didSetViewProps = self.platformView.setStaticViewProps()
            //if already set -> didSetViewProps will be false
            
            
//            #if DEBUG && os(iOS)
//            if #available(iOS 16.4, *) {
//                self.platformView.isInspectable = true
//            }
//            #endif
//            
//            /// So that the `View` adjusts its height automatically.
//            self.platformView.setContentHuggingPriority(.required, for: .vertical)
//            
//            /// Disables scrolling.
//            #if os(iOS)
//            self.platformView.scrollView.isScrollEnabled = false
//            #endif
//            
//            /// Set transparent background.
//            #if os(macOS)
//            self.platformView.setValue(false, forKey: "drawsBackground")
//            /// Equavalent to `.setValue(true, forKey: "drawsTransparentBackground")` on macOS 10.12 and before, which this library doesn't target.
//            #elseif os(iOS)
//            self.platformView.isOpaque = false
//            #endif
//            
            /// Receive messages from the web view.
            self.platformView.configuration.userContentController = .init()
            self.platformView.configuration.userContentController.add(self, name: "sizeChangeHandler")
            self.platformView.configuration.userContentController.add(self, name: "renderedContentHandler")
            
            do {
                if let htmlForLoad = try self.platformView.getHTML_ForLoad(css: self.cssType) {
                    self.platformView.loadHTMLString(htmlForLoad, baseURL: nil)
                } else {
                    //load content immediately
                    self.platformView.updateMarkdownContent(self.parent.markdownContent)
                    
                }
            } catch {
                print(error)
            }
            
//            let defaultStylesheetFileName = parent.defaultStyle.styleSheetName
//            guard let templateFileURL = Bundle.module.url(forResource: "template", withExtension: ""),
//                  let templateString = try? String(contentsOf: templateFileURL),
//                  let scriptFileURL = Bundle.module.url(forResource: "script", withExtension: ""),
//                  let script = try? String(contentsOf: scriptFileURL),
//                  let defaultStylesheetFileURL = Bundle.module.url(forResource: defaultStylesheetFileName, withExtension: ""),
//                  let defaultStylesheet = try? String(contentsOf: defaultStylesheetFileURL)
//            else { return }
//            let htmlString = templateString
//                .replacingOccurrences(of: "PLACEHOLDER_SCRIPT", with: script)
//                .replacingOccurrences(of: "PLACEHOLDER_STYLESHEET", with: self.parent.customStylesheet ?? defaultStylesheet)
//            self.platformView.loadHTMLString(htmlString, baseURL: nil)
        }
        
        /// Update the content on first finishing loading.
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            (webView as! CustomWebView).setDidLoadCss(self.cssType)
            
            (webView as! CustomWebView).updateMarkdownContent(self.parent.markdownContent)
        }
        
        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated {
                guard let url = navigationAction.request.url else { return .cancel }
                
                if let linkActivationHandler = self.parent.linkActivationHandler {
                    linkActivationHandler(url)
                } else {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #elseif os(iOS)
                    DispatchQueue.main.async {
                        Task { await UIApplication.shared.open(url) }
                    }
                    #endif
                }
                
                return .cancel
            } else {
                return .allow
            }
        }
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "sizeChangeHandler":
                guard let contentHeight = message.body as? CGFloat,
                      self.platformView.contentHeight != contentHeight
                else { return }
                self.platformView.contentHeight = contentHeight
                self.platformView.invalidateIntrinsicContentSize()
            case "renderedContentHandler":
                guard let renderedContentHandler = self.parent.renderedContentHandler,
                      let renderedContentBase64Encoded = message.body as? String,
                      let renderedContentBase64EncodedData: Data = .init(base64Encoded: renderedContentBase64Encoded),
                      let renderedContent = String(data: renderedContentBase64EncodedData, encoding: .utf8)
                else { return }
                renderedContentHandler(renderedContent)
            default:
                return
            }
        }
    }
    
    public class CustomWebView: WKWebView {
        var contentHeight: CGFloat = 0
        
        public override var intrinsicContentSize: CGSize {
            .init(width: super.intrinsicContentSize.width, height: self.contentHeight)
        }
        
        public var didSetStaticViewProps: Bool = false
        
        
        public func setStaticViewProps() -> Bool {
            if didSetStaticViewProps { return false }
            
            #if DEBUG && os(iOS)
            if #available(iOS 16.4, *) {
                self.isInspectable = true
            }
            #endif
            
            /// So that the `View` adjusts its height automatically.
            self.setContentHuggingPriority(.required, for: .vertical)
            
            /// Disables scrolling.
            #if os(iOS)
            self.scrollView.isScrollEnabled = false
            #endif
            
            /// Set transparent background.
            #if os(macOS)
            self.setValue(false, forKey: "drawsBackground")
            /// Equavalent to `.setValue(true, forKey: "drawsTransparentBackground")` on macOS 10.12 and before, which this library doesn't target.
            #elseif os(iOS)
            self.isOpaque = false
            #endif
            
            
            self.didSetStaticViewProps = true
            return true
        }
        
        public var didLoadCss: StyleSheetType? = nil
        
        public func setDidLoadCss(_ css: StyleSheetType) {
            self.didLoadCss = css
        }
        
        public func prepareForCacheReuse() {
            self.contentHeight = 0
            self.configuration.userContentController.removeAllScriptMessageHandlers()
            self.updateMarkdownContent("")
            
//            self.invalidateIntrinsicContentSize()
            
        }
        
        public func getHTML_ForLoad(css: StyleSheetType) throws -> String? {
            if let didLoadCss = self.didLoadCss, didLoadCss == css { return nil }
            
            
            let resolvedCss = try css.getCssValue()
            
            
            guard let templateFileURL = Bundle.module.url(forResource: "template", withExtension: ""),
                  let templateString = try? String(contentsOf: templateFileURL),
                  let scriptFileURL = Bundle.module.url(forResource: "script", withExtension: ""),
                  let script = try? String(contentsOf: scriptFileURL)
            else { throw Error.invalidDefaultStylesheet }
            
            
            let htmlString = templateString
                .replacingOccurrences(of: "PLACEHOLDER_SCRIPT", with: script)
                .replacingOccurrences(of: "PLACEHOLDER_STYLESHEET", with: resolvedCss)
            
            return htmlString
        }
        
        /// Disables scrolling.
        #if os(macOS)
        public override func scrollWheel(with event: NSEvent) {
            if event.deltaY == 0 {
                super.scrollWheel(with: event)
            } else {
                self.nextResponder?.scrollWheel(with: event)
            }
        }
        #endif
        
        /// Removes "Reload" from the context menu.
        #if os(macOS)
        public override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
            menu.items.removeAll { $0.identifier == .init("WKMenuItemIdentifierReload") }
        }
        #endif
        
        func updateMarkdownContent(_ markdownContent: String) {
            guard let markdownContentBase64Encoded = markdownContent.data(using: .utf8)?.base64EncodedString() else { return }
            
            self.callAsyncJavaScript("window.updateWithMarkdownContentBase64Encoded(`\(markdownContentBase64Encoded)`)", in: nil, in: .page, completionHandler: nil)
        }
    }
    
    
    public class WebViewPool {
        #if os(macOS)
        static let defaultInitialPoolSize: Int = 100
        #else
        static let defaultInitialPoolSize: Int = 10
        #endif
        
        static var shared: WebViewPool = WebViewPool(initialPoolSize: defaultInitialPoolSize)
        private var pool: [CustomWebView] = []

        private var sharedProcessPool: WKProcessPool
        
        
        init(initialPoolSize: Int? = nil) {
            self.sharedProcessPool = WKProcessPool()
            
            if let size = initialPoolSize {
                for _ in 0..<size {
                    let webView = CustomWebView()
                    pool.append(webView)
                }
            }
        }

        
        
        func getWebView() -> CustomWebView {
            if let webView = pool.first {
                pool.removeFirst()
                return webView
            } else {
                let webView = CustomWebView()
                webView.configuration.processPool = self.sharedProcessPool
                return webView
                
            }
        }

        func returnWebView(_ webView: CustomWebView) {
            webView.prepareForCacheReuse()
            pool.append(webView)
        }
    }

    
}
