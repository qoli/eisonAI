//
//  TagChipsView.swift
//  iOS (App)
//
//  Created by Codex on 2025/12/25.
//

import SwiftUI

struct TagChipsView: View {
    var tags: [String]

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}
