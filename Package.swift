// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "markdown-webview",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "MarkdownWebView",
            targets: ["MarkdownWebView"]),
    ],
    targets: [
        .target(
            name: "MarkdownWebView",
            resources: [.copy("Resources/template"),
                        .copy("Resources/script"),
                        .copy("Resources/stylesheets/default-macOS"),
                        .copy("Resources/stylesheets/default-iOS"),
                        .copy("Resources/stylesheets/messaging-macOS"),
                        .copy("Resources/stylesheets/messaging-iOS")
            ]),
    ]
)
