//
//  CaptureView.swift
//  FrameGate
//
//  Created by Franciss Peralta on 13/09/26.
//

import SwiftUI

struct CaptureView: View {
    var body: some View {
        VStack(spacing: 0) {
            CaptureHeader()
            CapturePreviewArea()
            ShutterPanel()
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct CaptureHeader: View {
    var body: some View {
        HStack {
            Text("Capture")
                .font(.headline)

            Spacer()

            NavigationLink {
                QueueView()
            } label: {
                Text("Queue (0)")
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
    var body: some View {
        ZStack {
            Color(.systemGray5)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    CaptureStatusPanel()
                    Spacer()
                    MetricsPanel()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    Rectangle()
                        .stroke(.secondary, lineWidth: 1)
                        .frame(width: 174, height: 128)

                    Text("ROI from mapped region")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
                .padding(.bottom, 112)
            }
        }
    }
}

private struct CaptureStatusPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Step 1 of 1")
            Text("blocked")
            Text("blocked by: sharpness")
            Text("0.0 ms/frame")
            Text("0 dropped")
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
    var body: some View {
        VStack(spacing: 0) {
            MetricRow(name: "sharpness", value: "0.00", state: "fail")
            Divider()
            MetricRow(name: "exposure", value: "0.00", state: "ok")
            Divider()
            MetricRow(name: "motion", value: "1.00", state: "fail")
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

private struct ShutterPanel: View {
    var body: some View {
        VStack(spacing: 14) {
            Button {
            } label: {
                Text("off")
                    .font(.caption.monospaced())
                    .frame(width: 82, height: 82)
                    .background(Circle().fill(Color(.systemGray6)))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
            }
            .buttonStyle(.plain)
            .disabled(true)

            VStack(spacing: 4) {
                Text("0 / 8 good frames")
                    .font(.subheadline.monospaced())
                Text("shutter disabled")
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
