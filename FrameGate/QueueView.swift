//
//  QueueView.swift
//  FrameGate
//
//  Created by Franciss Peralta on 13/09/26.
//

import SwiftUI

struct QueueView: View {
    @StateObject private var viewModel: QueueViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: QueueViewModel(container: container))
    }

    var body: some View {
        Group {
            if viewModel.rows.isEmpty {
                Text("No pending captures.")
                    .foregroundStyle(.secondary)
            } else {
                List(viewModel.rows) { row in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.subheadline.monospaced())
                            Text(row.detail).font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.canRetry {
                            Button("Retry") { viewModel.retryTapped(row.id) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }
        }
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

#Preview {
    NavigationStack {
        QueueView(container: AppContainer())
    }
}
