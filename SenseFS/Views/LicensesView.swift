//
//  LicensesView.swift
//  Open source licenses view
//

import SwiftUI

struct License: Identifiable {
    let id = UUID()
    let name: String
    let author: String
    let licenseType: String
    let url: String
    let licenseText: String
}

struct LicensesView: View {
    private let licenses: [License] = [
        License(
            name: "ZIPFoundation",
            author: "Thomas Zoechling",
            licenseType: "MIT",
            url: "https://github.com/weichsel/ZIPFoundation",
            licenseText: """
MIT License

Copyright (c) 2017-2025 Thomas Zoechling (https://www.peakstep.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
        ),
        License(
            name: "Swift Transformers",
            author: "Hugging Face",
            licenseType: "Apache 2.0",
            url: "https://github.com/huggingface/swift-transformers",
            licenseText: """
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

Copyright 2022 Hugging Face SAS.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""
        ),
        License(
            name: "Jinja",
            author: "John Mai",
            licenseType: "MIT",
            url: "https://github.com/maiqingqiang/Jinja",
            licenseText: """
MIT License

Copyright (c) 2024 John Mai

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
        ),
        License(
            name: "Swift Argument Parser",
            author: "Apple Inc.",
            licenseType: "Apache 2.0",
            url: "https://github.com/apple/swift-argument-parser",
            licenseText: """
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Runtime Library Exception to the Apache 2.0 License:

As an exception, if you use this Software to compile your source code and
portions of this Software are embedded into the binary product as a result,
you may redistribute such product without providing attribution as would
otherwise be required by Sections 4(a), 4(b) and 4(d) of the License.
"""
        ),
        License(
            name: "Swift Collections",
            author: "Apple Inc.",
            licenseType: "Apache 2.0",
            url: "https://github.com/apple/swift-collections",
            licenseText: """
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Runtime Library Exception to the Apache 2.0 License:

As an exception, if you use this Software to compile your source code and
portions of this Software are embedded into the binary product as a result,
you may redistribute such product without providing attribution as would
otherwise be required by Sections 4(a), 4(b) and 4(d) of the License.
"""
        )
    ]

    @State private var selectedLicense: License?

    var body: some View {
        NavigationSplitView {
            // Sidebar with license list
            List(licenses, selection: $selectedLicense) { license in
                VStack(alignment: .leading, spacing: 4) {
                    Text(license.name)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Text(license.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text(license.licenseType)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                .padding(.vertical, 4)
                .tag(license)
            }
            .navigationTitle("Open Source Licenses")
            .frame(minWidth: 250)
        } detail: {
            // Detail view with full license text
            if let license = selectedLicense {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(license.name)
                                .font(.title)
                                .fontWeight(.bold)

                            Text("by \(license.author)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Link(destination: URL(string: license.url)!) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                    Text(license.url)
                                }
                                .font(.caption)
                            }

                            Text(license.licenseType)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                        }

                        Divider()

                        // License text
                        Text(license.licenseText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                    .padding()
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Select a license to view")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    LicensesView()
        .frame(width: 900, height: 600)
}
