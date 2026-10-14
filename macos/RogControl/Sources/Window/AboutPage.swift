// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct AboutPage: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("ROG Control").font(.title.bold())
                    Text("Version \(version) for the ROG Zephyrus G14 (GA403WM)")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Author") {
                LabeledContent("Created by", value: "thanhnndev")
                Link("github.com/thanhnndev", destination: URL(string: "https://github.com/thanhnndev")!)
                Link("Project repository", destination: URL(string: "https://github.com/thanhnndev/ga403wm-hackintosh")!)
                LabeledContent("License", value: "Clear BSD License")
            }
            Section {
                ForEach(Credit.upstream) { credit in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Link(credit.name, destination: credit.url).fontWeight(.semibold)
                            Spacer()
                            Text(credit.license).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(credit.author).font(.callout)
                        Text(credit.role).font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Credits")
            } footer: {
                Text("Third-party code is not copied into this app unless stated. Full terms are in NOTICE.md in the repository.")
            }
        }
    }
}
