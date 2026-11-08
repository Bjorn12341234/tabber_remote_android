import RemoteKit
import SwiftUI

/// Tabber Studio's routing Flow, as its Routing window's Flow tab lays it out
/// (ui/routing_graph_view.py, ui/routing_flow_items.py): the tracks in mixer
/// order in the first column, the buses in columns by how deep they cascade,
/// and the master, the Output, last, centred on the tracks. Routes and sends
/// run from a card's output port to another's input port, Studio's teal; a
/// send's level rides on a pill; the default route to the master is dimmed,
/// and so is a muted card. Read only: the Routing page changes it.
struct FlowView: View {
    @Bindable var model: AppModel
    let routing: RoutingState
    /// nil: fitted to the screen, as Studio's Flow opens fitted to its window.
    @State private var zoom: CGFloat?
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        let layout = FlowLayout(routing: routing, mixer: model.state.mixer)
        GeometryReader { proxy in
            let fit = min(1, (proxy.size.width - 8) / layout.size.width, (proxy.size.height - 8) / layout.size.height)
            let scale = min(2, max(fit, 0.3) * (zoom ?? 1) * pinch)
            ScrollView([.horizontal, .vertical]) {
                graph(layout)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: layout.size.width * scale, height: layout.size.height * scale, alignment: .topLeading)
            }
            .defaultScrollAnchor(.topLeading)
            .scrollIndicators(.hidden)
            // Pinch to zoom in, as the wheel zooms Studio's Flow; a double tap fits it again.
            .simultaneousGesture(MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = min(2 / max(fit, 0.3), max(1, (zoom ?? 1) * value.magnification)) })
            .onTapGesture(count: 2) { withAnimation { zoom = nil } }
        }
        .background(Studio.bg0)
        .accessibilityIdentifier("flow")
    }

    private func graph(_ layout: FlowLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for wire in layout.wires {
                    context.stroke(wire.path, with: .color(Studio.accent.opacity(wire.strength)),
                                   style: StrokeStyle(lineWidth: wire.send == nil ? 2.2 : 1.8, lineCap: .round))
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .accessibilityHidden(true)
            ForEach(layout.wires.filter { $0.send != nil }) { wire in
                SendPill(send: wire.send!, spoken: sendWords(wire.send!))
                    .position(wire.middle)
                    .opacity(wire.strength < 1 ? 0.6 : 1)
            }
            ForEach(layout.nodes) { node in
                FlowNodeCard(node: node, summary: summary(node))
                    .frame(width: FlowLayout.nodeWidth, height: FlowLayout.nodeHeight)
                    .position(x: node.frame.midX, y: node.frame.midY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    /// What VoiceOver says for a card: where it goes; each send is its pill.
    private func summary(_ node: FlowLayout.Node) -> String {
        guard let source = routing.source(node.id) else { return "\(node.name), the output" }
        let words = "\(node.name), \(source.isBus ? "bus" : "track"), out to \(routing.outputName(of: source))"
        return node.muted ? words + ", muted" : words
    }

    private func sendWords(_ send: RoutingSend) -> String {
        let from = routing.source(send.stripID)?.name ?? "A track"
        let bus = routing.source(send.busID)?.name ?? "a bus"
        return "\(from) sends to \(bus) at \(send.levelLabel)\(send.preFader ? ", pre-fader" : "")"
    }
}

/// Studio's Flow layout, in the phone's points.
struct FlowLayout {
    static let nodeWidth: CGFloat = 132
    static let nodeHeight: CGFloat = 56
    static let columnGap: CGFloat = 76        // room for a send's pill
    static let rowGap: CGFloat = 14
    static let margin: CGFloat = 20

    struct Node: Identifiable {
        let id: String
        let kind: String          // "track", "bus" or "master"
        let name: String
        let color: String?
        let index: Int
        let muted: Bool
        let frame: CGRect
    }

    struct Wire: Identifiable {
        let id: String
        let path: Path
        let middle: CGPoint
        let send: RoutingSend?
        let strength: Double
    }

    var nodes: [Node] = []
    var wires: [Wire] = []
    var size = CGSize.zero

    init(routing: RoutingState, mixer: MixerState?) {
        let strips = mixer?.strips ?? []
        func strip(_ id: String) -> Strip? { strips.first { $0.id == id } }

        // Bus columns by cascade depth, as Studio relaxes them, bounded.
        let buses = routing.buses
        var depth = Dictionary(uniqueKeysWithValues: buses.map { ($0.stripID, 1) })
        let cascades = buses.compactMap { bus in depth[bus.output] == nil ? nil : (bus.stripID, bus.output) }
        for _ in 0..<max(1, buses.count) {
            var changed = false
            for (source, dest) in cascades {
                let next = (depth[source] ?? 1) + 1
                if next > (depth[dest] ?? 1), next <= buses.count {
                    depth[dest] = next
                    changed = true
                }
            }
            if !changed { break }
        }
        let maxDepth = depth.values.max() ?? 0
        func x(_ column: Int) -> CGFloat { Self.margin + CGFloat(column) * (Self.nodeWidth + Self.columnGap) }

        var columnY: [Int: CGFloat] = [:]
        func place(_ id: String, _ kind: String, _ name: String, _ index: Int, column: Int) {
            let y = columnY[column] ?? Self.margin
            nodes.append(Node(id: id, kind: kind, name: name, color: strip(id)?.color, index: index,
                              muted: strip(id)?.muted ?? false,
                              frame: CGRect(x: x(column), y: y, width: Self.nodeWidth, height: Self.nodeHeight)))
            columnY[column] = y + Self.nodeHeight + Self.rowGap
        }
        for (index, track) in routing.tracks.enumerated() { place(track.stripID, "track", track.name, index, column: 0) }
        for (index, bus) in buses.enumerated() { place(bus.stripID, "bus", bus.name, index, column: depth[bus.stripID] ?? 1) }
        // The master: last column, centred on the tracks.
        let tracksHeight = max(Self.nodeHeight, (columnY[0] ?? Self.margin) - Self.margin - Self.rowGap)
        let masterY = Self.margin + max(0, (tracksHeight - Self.nodeHeight) / 2)
        nodes.append(Node(id: RoutingState.master, kind: "master", name: "Master", color: nil, index: 0, muted: false,
                          frame: CGRect(x: x(maxDepth + 1), y: masterY, width: Self.nodeWidth, height: Self.nodeHeight)))

        let frames = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.frame) })
        func wire(_ id: String, from: String, to: String, send: RoutingSend?, strength: Double) {
            guard let a = frames[from], let b = frames[to] else { return }
            let start = CGPoint(x: a.maxX, y: a.midY), end = CGPoint(x: b.minX, y: b.midY)
            let pull = max(30, (end.x - start.x) / 2)
            var path = Path()
            path.move(to: start)
            path.addCurve(to: end, control1: CGPoint(x: start.x + pull, y: start.y), control2: CGPoint(x: end.x - pull, y: end.y))
            let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            wires.append(Wire(id: id, path: path, middle: middle, send: send, strength: strength))
        }
        for source in routing.sources {
            let muted = strip(source.stripID)?.muted ?? false
            let toMaster = source.output == RoutingState.master
            wire("route:\(source.stripID)", from: source.stripID, to: source.output, send: nil,
                 strength: toMaster ? 0.35 : (muted ? 0.45 : 1))         // the default route, dimmed
        }
        for send in routing.sends {
            let muted = strip(send.stripID)?.muted ?? false
            wire("send:\(send.id)", from: send.stripID, to: send.busID, send: send, strength: muted ? 0.45 : 1)
        }
        let right = nodes.map(\.frame.maxX).max() ?? 0, bottom = nodes.map(\.frame.maxY).max() ?? 0
        size = CGSize(width: right + Self.margin, height: bottom + Self.margin)
    }
}

/// One card: the name on its colour, as the mixer's strip header, and what it is.
private struct FlowNodeCard: View {
    let node: FlowLayout.Node
    let summary: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Studio.radiusCard, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text(node.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Studio.text1)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(header, in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
            Text(kind)
                .font(.caption)
                .foregroundStyle(Studio.text2)
                .padding(.leading, 8)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(node.kind == "master" ? Studio.bg3 : Studio.bg2, in: shape)
        .overlay(shape.strokeBorder(Studio.edge))
        .overlay(alignment: .leading) { if node.kind != "track" { port(Studio.text2).offset(x: -5) } }
        .overlay(alignment: .trailing) { if node.kind != "master" { port(Studio.accent).offset(x: 5) } }
        .opacity(node.muted ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityIdentifier("flow-\(node.name)")
    }

    private var kind: String {
        switch node.kind {
        case "track": "Track"
        case "bus": "Bus"
        default: "Output"
        }
    }

    private var header: Color {
        // Darker than the mixer's chip: at the fitted size the name is small,
        // and small text needs more contrast.
        node.kind == "track" ? Studio.track(node.color, index: node.index).opacity(0.4) : Studio.bg3
    }

    /// Studio's ports: outputs teal, inputs light, ringed in the canvas colour.
    private func port(_ fill: Color) -> some View {
        Circle().fill(fill).frame(width: 10, height: 10)
            .overlay(Circle().stroke(Studio.bg0, lineWidth: 2))
    }
}

/// A send's level on its wire, as Studio's pill shows it, with Pre-fader.
private struct SendPill: View {
    let send: RoutingSend
    let spoken: String

    var body: some View {
        Text(send.preFader ? "\(send.levelLabel) pre" : send.levelLabel)
            .font(Studio.counter(.caption2))
            .foregroundStyle(Studio.text1)
            .accessibilityLabel(spoken)           // read as text, not something to tap
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Studio.bg3, in: Capsule())
            .overlay(Capsule().strokeBorder(Studio.accent.opacity(0.6), lineWidth: 1))
            .fixedSize()
    }
}
