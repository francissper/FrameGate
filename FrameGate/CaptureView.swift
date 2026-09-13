//
//  CaptureView.swift
//  FrameGate
//
//  Created by Franciss Peralta on 13/09/26.
//

import SwiftUI

struct CaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()

    var body: some View {
        VStack(spacing: 0) {
            CaptureHeader(queueCount: viewModel.state.queueCount)
            CapturePreviewArea(state: viewModel.state) { event in
                viewModel.send(event)
            }
            ShutterPanel(state: viewModel.state) {
                viewModel.send(.shutterTapped)
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { viewModel.send(.appeared) }
        .onDisappear { viewModel.send(.disappeared) }
    }
}

private struct CaptureHeader: View {
    let queueCount: Int

    var body: some View {
        HStack {
            Text("Capture")
                .font(.headline)

            Spacer()

            NavigationLink {
                QueueView()
            } label: {
                Text("Queue (\(queueCount))")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct CapturePreviewArea: View {
    let state: CaptureScreenState
    let send: (CaptureEvent) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(.systemGray5)
                    .onAppear { send(.geometryChanged(proxy.size)) }
                    .onChange(of: proxy.size) { _, size in
                        send(.geometryChanged(size))
                    }

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        CaptureStatusPanel(state: state)
                        Spacer()
                        MetricsPanel(state: state)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        OutlineView(rect: state.outline)

                        Text("ROI from mapped region")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 32)
                    .padding(.bottom, 112)
                }

                if let errorText = state.errorText {
                    Text(errorText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(Color(.systemBackground))
                        .overlay {
                            Rectangle().stroke(Color(.separator), lineWidth: 1)
                        }
                        .padding(16)
                }
            }
        }
    }
}

private struct CaptureStatusPanel: View {
    let state: CaptureScreenState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(state.stepText)
            Text(state.phaseText)
            Text(state.blockingText)
            Text(state.millisecondsText)
            Text(state.droppedText)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.primary)
        .padding(10)
        .frame(width: 156, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay {
            Rectangle().stroke(Color(.separator), lineWidth: 1)
        }
    }
}

private struct MetricsPanel: View {
    let state: CaptureScreenState

    var body: some View {
        VStack(spacing: 0) {
            MetricRow(name: "sharpness", value: state.sharpnessText, state: state.sharpnessState)
            Divider()
            MetricRow(name: "exposure", value: state.exposureText, state: state.exposureState)
            Divider()
            MetricRow(name: "motion", value: state.motionText, state: state.motionState)
        }
        .font(.caption.monospaced())
        .frame(width: 148)
        .background(Color(.systemBackground))
        .overlay {
            Rectangle().stroke(Color(.separator), lineWidth: 1)
        }
    }
}

private struct MetricRow: View {
    let name: String
    let value: String
    let state: String

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
            Text(state)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }
}

private struct OutlineView: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .stroke(.secondary, lineWidth: 1)
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .opacity(rect.width > 0 && rect.height > 0 ? 1 : 0.35)
    }
}

private struct ShutterPanel: View {
    let state: CaptureScreenState
    let fire: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Button(action: fire) {
                Text(state.shutterText)
                    .font(.caption.monospaced())
                    .frame(width: 82, height: 82)
                    .background(Circle().fill(Color(.systemGray6)))
                    .overlay {
                        Circle()
                            .strokeBorder(state.isShutterEnabled ? Color.primary : Color.secondary.opacity(0.35),
                                          style: StrokeStyle(lineWidth: state.isShutterEnabled ? 2 : 1,
                                                             dash: state.isShutterEnabled ? [] : [3, 3]))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!state.isShutterEnabled)

            VStack(spacing: 4) {
                Text(state.goodFramesText)
                    .font(.subheadline.monospaced())
                Text(state.shutterSubtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 174)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
}
