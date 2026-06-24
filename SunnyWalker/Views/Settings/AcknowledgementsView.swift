// SunnyWalker — AcknowledgementsView.swift
// Open-source attribution screen. Required to fulfil the MIT license notice
// obligation for third-party code bundled in the app (ConfettiSwiftUI):
// the MIT license requires its copyright + permission text be reproduced in
// distributions. This screen ships that text inside the app bundle.
//
// When adding a new third-party package, add an entry to `credits` below.

import SwiftUI

struct AcknowledgementsView: View {

    /// One bundled open-source component and its license details.
    private struct Credit: Identifiable {
        let id = UUID()
        let name: String
        let license: String
        let copyright: String
        let source: String
        /// Full license text reproduced verbatim (required by MIT).
        let licenseText: String
    }

    private let credits: [Credit] = [
        Credit(
            name: "ConfettiSwiftUI",
            license: "MIT License",
            copyright: "© 2020 Simon Bachmann",
            source: "https://github.com/simibac/ConfettiSwiftUI",
            licenseText: Self.mitLicenseText
        )
    ]

    var body: some View {
        List {
            Section(footer: Text("third_party_ack_footer")) {
                ForEach(credits) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: c.name)
                            .font(.headline)
                            .foregroundStyle(SunnyColors.forestDeep)
                        Text(verbatim: c.license)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SunnyColors.skyBlue)
                        Text(verbatim: c.copyright)
                            .font(.footnote)
                            .foregroundStyle(SunnyColors.sunnyGray)
                        Text(verbatim: c.source)
                            .font(.footnote)
                            .foregroundStyle(SunnyColors.skyBlue)
                            .textSelection(.enabled)
                        Text(verbatim: c.licenseText)
                            .font(.caption2)
                            .foregroundStyle(SunnyColors.sunnyGray)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle(Text("third_party_licenses_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// MIT license — reproduced verbatim to satisfy the notice requirement.
    private static let mitLicenseText = """
    Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal \
    in the Software without restriction, including without limitation the rights \
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is \
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all \
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
    SOFTWARE.
    """
}

#Preview {
    NavigationStack { AcknowledgementsView() }
}
