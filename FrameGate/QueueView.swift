//
//  QueueView.swift
//  FrameGate
//
//  Created by Franciss Peralta on 13/09/26.
//

import SwiftUI

struct QueueView: View {
    private let rows = [
        QueueRow(title: "IMG_0412.heic", detail: "uploading - attempt 1", canRetry: false),
        QueueRow(title: "IMG_0411.heic", detail: "pending - attempt 2 - next attempt 09:44", canRetry: false),
        QueueRow(title: "IMG_0410.heic", detail: "failed - attempt 3", canRetry: true),
        QueueRow(title: "IMG_0409.heic", detail: "uploaded - attempt 1", canRetry: false),
        QueueRow(title: "IMG_0408.heic", detail: "pending - attempt 1 - next attempt 09:47", canRetry: false)
    ]

    var body: some View {
        List(rows) { row in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.subheadline.monospaced())
                    Text(row.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if row.canRetry {
                    Button("Retry") {
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 6)
        }
        .listStyle(.plain)
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text("no thumbnails - no sections - no swipe actions")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
        }
    }
}

private struct QueueRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let canRetry: Bool
}

#Preview {
    NavigationStack {
        QueueView()
    }
}
