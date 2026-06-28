import SwiftUI

struct ThirdPartyAcknowledgementsView: View {
    private let projects = ThirdPartyAcknowledgement.projects

    var body: some View {
        List {
            Section {
                Text(AppLocalizations.string(
                    "acknowledgements.intro",
                    defaultValue: "MewyAI uses the following open source projects to build its Markdown, network image, and LaTeX rendering experience. Thanks to the authors and contributors of these projects."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(projects) { project in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(project.name)
                                .font(.headline)
                            Spacer()
                            Text(project.license)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(project.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(project.attribution)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Link(project.url.absoluteString, destination: project.url)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(AppLocalizations.string(
                    "acknowledgements.projects.header",
                    defaultValue: "Open Source Projects"
                ))
            } footer: {
                Text(AppLocalizations.string(
                    "acknowledgements.projects.footer",
                    defaultValue: "Full license texts are distributed with the app. Project copyrights remain with their original authors."
                ))
            }
        }
        .navigationTitle(AppLocalizations.string(
            "acknowledgements.title",
            defaultValue: "Open Source Acknowledgements"
        ))
    }
}

private struct ThirdPartyAcknowledgement: Identifiable {
    let id: String
    let name: String
    let license: String
    let description: String
    let attribution: String
    let url: URL

    static let projects: [ThirdPartyAcknowledgement] = [
        ThirdPartyAcknowledgement(
            id: "swift-markdown-ui",
            name: "MarkdownUI",
            license: "MIT",
            description: AppLocalizations.string(
                "acknowledgements.project.markdownUI.description",
                defaultValue: "Renders Markdown content in SwiftUI."
            ),
            attribution: "Copyright (c) 2020 Guillermo Gonzalez",
            url: URL(string: "https://github.com/gonzalezreal/swift-markdown-ui")!
        ),
        ThirdPartyAcknowledgement(
            id: "networkimage",
            name: "NetworkImage",
            license: "MIT",
            description: AppLocalizations.string(
                "acknowledgements.project.networkImage.description",
                defaultValue: "Remote image loading component used by MarkdownUI."
            ),
            attribution: "Copyright (c) 2020 Guille Gonzalez",
            url: URL(string: "https://github.com/gonzalezreal/NetworkImage")!
        ),
        ThirdPartyAcknowledgement(
            id: "swift-cmark",
            name: "swift-cmark / cmark-gfm",
            license: "BSD / MIT",
            description: AppLocalizations.string(
                "acknowledgements.project.swiftCmark.description",
                defaultValue: "CommonMark and GitHub Flavored Markdown parser used by MarkdownUI."
            ),
            attribution: "Copyright (c) 2014 John MacFarlane and contributors",
            url: URL(string: "https://github.com/swiftlang/swift-cmark")!
        ),
        ThirdPartyAcknowledgement(
            id: "mathjax",
            name: "MathJax",
            license: "Apache-2.0",
            description: AppLocalizations.string(
                "acknowledgements.project.mathJax.description",
                defaultValue: "Renders LaTeX math formulas as SVG."
            ),
            attribution: "Copyright MathJax Consortium and contributors",
            url: URL(string: "https://github.com/mathjax/MathJax")!
        ),
    ]
}

#Preview {
    NavigationStack {
        ThirdPartyAcknowledgementsView()
    }
}
