//
//  ContentView.swift
//  FrameGate
//
//  Created by Franciss Peralta on 11/09/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var container = AppContainer()

    var body: some View {
        NavigationStack {
            CaptureView(container: container)
        }
        .task {
            await container.restoreQueue()
            container.startDraining()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                container.startDraining()
            } else {
                container.stopDraining()
            }
        }
    }
}

#Preview {
    ContentView()
}
