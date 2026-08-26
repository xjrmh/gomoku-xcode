import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SharePayload: Transferable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { payload in payload.pngData }
    }
}

@MainActor
enum ShareCardRenderer {
    static func render(session: GameSession, palette: GomokuPalette, colorScheme: ColorScheme) -> SharePayload? {
        let view = ShareCardView(session: session, palette: palette)
            .environment(\.colorScheme, colorScheme)
            .frame(width: 900, height: 1_160)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #if os(iOS)
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        return SharePayload(pngData: data)
        #elseif os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return SharePayload(pngData: data)
        #else
        return nil
        #endif
    }
}

private struct ShareCardView: View {
    let session: GameSession
    let palette: GomokuPalette

    var body: some View {
        VStack(spacing: 34) {
            Text("Just Gomoku")
                .font(.system(size: 52, weight: .bold, design: .rounded))
            StaticBoardView(
                board: session.board,
                boardSize: session.boardSize,
                lastMove: session.moves.last?.pos,
                winningLine: session.outcome.winningLine,
                palette: palette
            )
            .frame(width: 820, height: 820)
            HStack(spacing: 18) {
                StoneDot(player: session.outcome.winner)
                    .frame(width: 28, height: 28)
                Text(resultTitle)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
            }
            Text("\(session.configuration.mode.title) · \(session.boardSize)×\(session.boardSize) · \(session.moves.count) moves")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Black \(time(session.clocks.black))  ·  White \(time(session.clocks.white))")
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(palette.background)
    }

    private var resultTitle: String {
        session.outcome.winner.map { "\($0.name) wins" } ?? "Draw"
    }

    private func time(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
