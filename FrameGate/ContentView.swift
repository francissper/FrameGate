//
//  ContentView.swift
//  FrameGate
//
//  Created by Franciss Peralta on 11/09/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var container = AppContainer()

    var body: some View {
        NavigationStack {
            CaptureView(container: container)
        }
        .task { await container.restoreQueue() }
    }
}

#Preview {
    ContentView()
}
