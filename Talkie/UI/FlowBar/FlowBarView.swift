import SwiftUI

struct FlowBarView: View {
    let coordinator: DictationCoordinator
    let recorder: AudioRecorder

    @State private var levels: [Float] = Array(repeating: 0, count: 24)
    private let timer = Timer.publish(every: 1.0 / 24, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch coordinator.state {
            case .idle:
                Capsule().fill(.black.opacity(0.55))
                    .frame(width: 56, height: 7)
            case .recording:
                pill {
                    HStack(spacing: 2.5) {
                        ForEach(levels.indices, id: \.self) { i in
                            Capsule().fill(.white)
                                .frame(width: 2.5, height: max(3, CGFloat(levels[i]) * 26))
                        }
                    }
                }
            case .transcribing, .cleaning, .inserting:
                pill {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Polishing…").font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                }
            case .error(let message):
                pill(background: .red.opacity(0.85)) {
                    Text(message).font(.caption).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .frame(width: 260, height: 56, alignment: .bottom)
        .padding(.bottom, 2)
        .animation(.spring(duration: 0.25), value: coordinator.state)
        .onReceive(timer) { _ in
            guard coordinator.state == .recording else { return }
            levels.removeFirst()
            levels.append(recorder.latestLevel)
        }
    }

    private func pill(background: Color = .black.opacity(0.78),
                      @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(background, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }
}
