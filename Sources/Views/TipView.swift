import SwiftUI

/// Content of the floating tip: preview, sizes, type list, reduction buttons and undo.
struct TipView: View {
    @ObservedObject var controller: ClipboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let snap = controller.snapshot, snap.summary.kind != .empty {
                preview(snap)
                typeList(snap)
                reductionButtons
            } else {
                Text("Clipboard is empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            if let notice = controller.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .onHover { controller.tip.setHovering($0) }
    }

    private var header: some View {
        HStack {
            let kind = controller.snapshot?.summary.kind ?? .empty
            Label(controller.snapshot?.summary.title ?? kind.title, systemImage: kind.symbol)
                .font(.headline)
            Spacer()
            if controller.isConverting { ProgressView().controlSize(.small) }
            if !controller.log.isEmpty {
                Button("Undo (U)") { controller.undoLast() }.controlSize(.small)
            }
            Button { controller.tip.hide() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close (Esc)")
        }
    }

    @ViewBuilder
    private func preview(_ snap: ClipSnapshot) -> some View {
        if let thumb = snap.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 140)
        } else if let text = snap.text {
            Text(text.isEmpty ? "(empty string)" : text)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if let url = snap.fileURLs.first {
            Text(url.path).font(.caption).lineLimit(2).truncationMode(.middle)
        }
        Text(sizeLine(snap)).font(.caption).foregroundStyle(.secondary)
    }

    private func sizeLine(_ snap: ClipSnapshot) -> String {
        var parts: [String] = []
        if let px = snap.pixelSize { parts.append("\(Int(px.width))×\(Int(px.height)) px") }
        if let chars = snap.characterCount { parts.append("\(chars.formatted()) characters") }
        if snap.fileURLs.count > 0 { parts.append("\(snap.fileURLs.count) file\(snap.fileURLs.count == 1 ? "" : "s")") }
        parts.append(ClipboardInspector.bytes(snap.totalBytes) + " total")
        return parts.joined(separator: " · ")
    }

    private func typeList(_ snap: ClipSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(snap.types.prefix(8)) { type in
                HStack {
                    Text(type.name).lineLimit(1).help(type.raw)
                    Spacer()
                    Text(type.bytes.map(ClipboardInspector.bytes) ?? "—").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            if snap.types.count > 8 {
                Text("+ \(snap.types.count - 8) more types").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var reductionButtons: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow { button(.plainText); button(.firstFile) }
            GridRow { button(.pngImage); button(.singleLine) }
        }
    }

    private func button(_ reduction: Reduction) -> some View {
        Button { controller.reduce(reduction) } label: {
            HStack(spacing: 4) {
                Text(reduction.key.uppercased()).font(.caption.monospaced().bold())
                Text(reduction.title).font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!controller.canApply(reduction) || controller.isConverting)
        .help("Reduce the clipboard to \(reduction.title) (\(reduction.key.uppercased()))")
    }
}
