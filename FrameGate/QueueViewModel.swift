//
//  QueueViewModel.swift
//  FrameGate
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation
import Combine
import FrameGateCore

struct QueueRowState: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
    let canRetry: Bool
}

@MainActor
final class QueueViewModel: ObservableObject {

    @Published private(set) var rows: [QueueRowState] = []

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer) {
        self.container = container
        container.queue.state
            .receive(on: DispatchQueue.main)
            .map { records in records.map { Self.row(from: $0) } }
            .sink { [weak self] rows in self?.rows = rows }
            .store(in: &cancellables)
    }

    func retryTapped(_ id: UUID) {
        Task { try? await container.queue.retryManually(id) }
    }
}

private extension QueueViewModel {

    static func row(from record: CaptureRecord) -> QueueRowState {
        let name = (record.framePath as NSString).lastPathComponent
        let detail: String
        switch record.status {
        case .pending:
            if let next = record.nextAttemptAt {
                detail = "pending · attempt \(record.attempts) · next at \(next.formatted(date: .omitted, time: .shortened))"
            } else {
                detail = "pending · attempt \(record.attempts)"
            }
        case .uploaded:
            detail = "uploaded · attempt \(record.attempts)"
        case .failed:
            detail = "failed · attempt \(record.attempts)"
        }
        return QueueRowState(id: record.captureID, title: name, detail: detail,
                             canRetry: record.status == .failed)
    }
}
