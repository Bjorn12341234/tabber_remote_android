import RemoteKit
import SwiftUI

/// Tabber Studio's Routing panel as a list for one thumb: each track with its
/// Output and its Sends, then each bus with its Output and what feeds it. In
/// Tabber Studio the Routing panel can sit as a tab beside the Mixer; here it
/// is the Mixer's other view.
struct RoutingView: View {
    @Bindable var model: AppModel
    let routing: RoutingState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if routing.buses.isEmpty {
                    Text("No buses yet. Add one with the mixer's + Bus button in Tabber Studio, and route to it here.")
                        .font(.subheadline)
                        .foregroundStyle(Studio.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("no-buses")
                }
                Heading(text: "Tracks")
                ForEach(Array(routing.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRouting(model: model, routing: routing, source: track, index: index)
                }
                if !routing.buses.isEmpty {
                    Heading(text: "Buses")
                    ForEach(routing.buses) { bus in
                        BusRouting(model: model, routing: routing, bus: bus)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .bottom)      // nothing reads through behind the transport
    }
}

private struct Heading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Studio.text1)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A track: its colour and name, where its sound goes, and its sends.
private struct TrackRouting: View {
    @Bindable var model: AppModel
    let routing: RoutingState
    let source: RoutingSource
    let index: Int

    var body: some View {
        let sends = routing.sends(from: source.stripID)
        let unsent = routing.buses.filter { bus in !sends.contains { $0.busID == bus.stripID } }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(source.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Studio.text1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, 2)
            OutputMenu(model: model, routing: routing, source: source)
            ForEach(sends) { send in
                SendRow(model: model, send: send, trackName: source.name, busName: routing.source(send.busID)?.name ?? "Bus")
            }
            if !unsent.isEmpty {
                Menu {
                    ForEach(unsent) { bus in
                        Button("Send to \(bus.name)") { model.addSend(from: source.stripID, to: bus.stripID) }
                    }
                } label: {
                    Label("Add send", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Studio.text1)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .accessibilityIdentifier("add-send-\(source.name)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .studioCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-\(source.name)")
    }

    private var color: Color {
        let track = model.state.tracks.first { $0.id == source.stripID }
        return Studio.track(track?.color, index: index)
    }
}

/// A bus: where its sound goes, and what feeds it.
private struct BusRouting: View {
    @Bindable var model: AppModel
    let routing: RoutingState
    let bus: RoutingSource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bus.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Studio.text1)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 2)
            OutputMenu(model: model, routing: routing, source: bus)
            Text(fedBy)
                .font(.subheadline)
                .foregroundStyle(Studio.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .accessibilityIdentifier("fed-\(bus.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .studioCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-\(bus.name)")
    }

    private var fedBy: String {
        let feeding = routing.feeding(bus.stripID)
        let outputs = feeding.outputs.map(\.name)
        let sends = feeding.sends.compactMap { routing.source($0.stripID)?.name }
        var lines: [String] = []
        if !outputs.isEmpty { lines.append("Output from \(Self.list(outputs))") }
        if !sends.isEmpty { lines.append("Sends from \(Self.list(sends))") }
        return lines.isEmpty ? "Nothing feeds it yet." : lines.joined(separator: "\n")
    }

    static func list(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}

/// Where a source's sound goes: the master or a bus, chosen from a menu as
/// Tabber Studio's header Output menu offers them. A bus that would feed back
/// into this one is shown, and can't be chosen.
private struct OutputMenu: View {
    @Bindable var model: AppModel
    let routing: RoutingState
    let source: RoutingSource

    var body: some View {
        let current = routing.outputName(of: source)
        Menu {
            Picker("Output", selection: Binding(get: { source.output }, set: { model.setOutput(source, to: $0) })) {
                Text("Master").tag(RoutingState.master)
                ForEach(routing.outputs(for: source)) { bus in
                    if let loop = source.isBus ? routing.wouldLoop(source.stripID, into: bus.stripID) : nil {
                        Text("\(bus.name), would loop: \(loop.joined(separator: " → "))").tag(bus.stripID)
                            .selectionDisabled()
                    } else {
                        Text(bus.name).tag(bus.stripID)
                    }
                }
            }
        } label: {
            HStack {
                Text("Output")
                    .font(.subheadline)
                    .foregroundStyle(Studio.text2)
                Spacer()
                Text(current)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(source.output == RoutingState.master ? Studio.text1 : Studio.accent)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Studio.text2)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
            .opacity(model.pending.contains("output-\(source.stripID)") ? 0.5 : 1)
        }
        .accessibilityLabel("Output of \(source.name)")
        .accessibilityValue(current)
        .accessibilityIdentifier("output-\(source.name)")
    }
}

/// One send, as Tabber Studio's mixer draws it: the bus name, a thin track
/// with the thumb at the level, and PRE when it taps before the fader. Drag
/// from where it is (no jump on touch); double-tap for silence, as Tabber
/// Studio's double-click does.
private struct SendRow: View {
    @Bindable var model: AppModel
    let send: RoutingSend
    let trackName: String
    let busName: String
    @State private var dragLevel: Double?
    @State private var dragStart: Double?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                adjustable(VStack(alignment: .leading, spacing: 4) { name; bar })
                HStack(spacing: 10) { pre; remove }
            }
        } else {
            HStack(spacing: 10) { adjustable(HStack(spacing: 10) { name; bar }); pre; remove }
        }
    }

    /// The bus, the level and the bar are one control for VoiceOver: "Send to
    /// Reverb, -12.0 decibels", swiped up and down in steps.
    private func adjustable(_ content: some View) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Send to \(busName)")
            .accessibilityValue(spoken(send.levelDB))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.05 : -0.05
                model.setSendLevel(send, max(0, min(1, send.level + step)))
            }
            .accessibilityIdentifier("send-\(trackName)-\(busName)")
    }

    /// The bus and the level in Tabber Studio's words, never cut short.
    private var name: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(busName)
                .font(.subheadline)
                .foregroundStyle(Studio.text2)
            Text(dragLevel.map(SendLevel.label) ?? send.levelLabel)
                .font(Studio.counter(.caption))
                .foregroundStyle(Studio.text2)
        }
        .fixedSize()
        .frame(minWidth: 72, alignment: .leading)
    }

    private var bar: some View {
        let level = dragLevel ?? send.level
        return GeometryReader { proxy in
            SendTrack(level: level, width: proxy.size.width)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        let start = dragStart ?? send.level
                        dragStart = start
                        let next = max(0, min(1, start + Double(drag.translation.width / max(1, proxy.size.width))))
                        dragLevel = next
                        model.setSendLevel(send, next)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        Task { try? await Task.sleep(for: .milliseconds(400)); dragLevel = nil }
                    })
                .onTapGesture(count: 2) { model.setSendLevel(send, 0) }
        }
        .frame(minWidth: 60, minHeight: 44, maxHeight: 44)
    }

    private var pre: some View {
        LetterButton(letter: "PRE", isOn: send.preFader, onColor: Studio.text2,
                     spoken: "Pre-fader, send to \(busName)") {
            model.setPreFader(send, !send.preFader)
        }
        .accessibilityIdentifier("pre-\(trackName)-\(busName)")
    }

    private var remove: some View {
        Button { model.removeSend(send) } label: {
            Image(systemName: "minus.circle")
                .font(.body)
                .foregroundStyle(Studio.text2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove send to \(busName)")
        .accessibilityIdentifier("remove-send-\(trackName)-\(busName)")
    }

    private func spoken(_ db: Double?) -> String {
        guard let db else { return "silent" }
        return String(format: "%.1f decibels", db)
    }
}

/// The send's track: a thin neutral line, filled to the thumb.
private struct SendTrack: View {
    let level: Double
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            let thumb: CGFloat = 7, track: CGFloat = 4
            let mid = size.height / 2
            let x = thumb + CGFloat(level) * max(0, size.width - 2 * thumb)
            let line = Path(roundedRect: CGRect(x: 0, y: mid - track / 2, width: size.width, height: track),
                            cornerRadius: track / 2)
            context.fill(line, with: .color(Studio.bg0))
            if level > 0 {
                let fill = Path(roundedRect: CGRect(x: 0, y: mid - track / 2, width: x, height: track), cornerRadius: track / 2)
                context.fill(fill, with: .color(Studio.text3))
            }
            let dot = Path(ellipseIn: CGRect(x: x - thumb, y: mid - thumb, width: thumb * 2, height: thumb * 2))
            context.fill(dot, with: .color(level > 0 ? Studio.text1 : Studio.text3))
        }
    }
}
