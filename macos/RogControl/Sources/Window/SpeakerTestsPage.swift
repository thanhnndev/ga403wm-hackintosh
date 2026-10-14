// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct SpeakerTestsPage: View {
    @Bindable var tests: SpeakerTestModel
    @State private var expanded: Set<String> = []

    var body: some View {
        Form {
            Section {
                Picker("Play through", selection: $tests.target) {
                    ForEach(PlaybackTarget.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(tests.playing != nil)
                if !tests.error.isEmpty { Notice(text: tests.error, kind: .caution) }
                if !tests.tests.isEmpty {
                    LabeledContent("Heard", value: "\(tests.heard.count) of \(tests.tests.count)")
                }
            } footer: {
                Text("Built-in output is the raw hardware path. ROG Speakers goes through the DSP profile.")
            }
            if tests.tests.isEmpty {
                Section { Notice(text: "The speaker test set is missing from this build.", kind: .caution) }
            }
            Section {
                ForEach(tests.groups, id: \.name) { group in
                    DisclosureGroup(isExpanded: expansion(of: group.name)) {
                        ForEach(group.tests) { test in SpeakerTestRow(tests: tests, test: test) }
                    } label: {
                        HStack {
                            Text(group.name).fontWeight(.semibold)
                            Spacer()
                            Text("\(group.tests.filter { tests.heard.contains($0.file) }.count) of \(group.tests.count) heard")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Speaker Tests")
        .onDisappear { tests.stop() }
    }

    private func expansion(of group: String) -> Binding<Bool> {
        Binding {
            expanded.contains(group)
        } set: { isOpen in
            if isOpen { expanded.insert(group) } else { expanded.remove(group) }
        }
    }
}
