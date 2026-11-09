import RemoteKit
import SwiftUI

/// Tabber Studio's routing Flow, as its Routing window's Flow tab lays it out
/// (ui/routing_graph_view.py, ui/routing_flow_items.py): the tracks in mixer
/// order in the first column, the buses in columns by how deep they cascade,
/// and the master, the Output, last, centred on the tracks. Routes and sends
/// run from a card's output port to another's input port, Studio's teal; a
/// send's level rides on a pill; the default route to the master is dimmed,
/// and so is a muted card.
///
/// Wiring by hand, as Studio's Flow does it: drag from a card's output port
/// onto a bus or the Master. On the Master the output goes back to the
/// master; on a bus a track chooses its output or a send there (Studio's
/// plain or Option drag), and a bus moves its output, refused in Studio's
/// words when that would loop. Nothing is gesture-only: press and hold a card
/// for the same as a menu, with its sends to take away, and VoiceOver offers
/// them as actions. Each change is one undo step on the computer.
struct FlowView: View {
    @Bindable var model: AppModel
    let routing: RoutingState
    /// nil: fitted to the screen, as Studio's Flow opens fitted to its window.
    @State private var zoom: CGFloat?
    @GestureState private var pinch: CGFloat = 1
    /// The wire being dragged out of a card's output port, in the graph's points.
    @State private var dragging: WireDrag?
    /// A track's wire dropped on a bus, waiting for its choice: output or send.
    @State private var dropped: WireDrop?
    /// Why a drop was refused, in Tabber Studio's words.
    @State private var refusal: String?

    static let space = "flow-graph"

    var body: some View {
        let layout = FlowLayout(routing: routing, mixer: model.state.mixer)
        GeometryReader { proxy in
            let fit = min(1, (proxy.size.width - 8) / layout.size.width, (proxy.size.height - 8) / layout.size.height)
            let scale = min(2, max(fit, 0.3) * (zoom ?? 1) * pinch)
            ScrollView([.horizontal, .vertical]) {
                graph(layout, scale: scale)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: layout.size.width * scale, height: layout.size.height * scale, alignment: .topLeading)
            }
            .scrollDisabled(dragging != nil)
            .defaultScrollAnchor(.topLeading)
            .scrollIndicators(.hidden)
            // Pinch to zoom in, as the wheel zooms Studio's Flow; a double tap fits it again.
            .simultaneousGesture(MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = min(2 / max(fit, 0.3), max(1, (zoom ?? 1) * value.magnification)) })
            .onTapGesture(count: 2) { withAnimation { zoom = nil } }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Drag from a teal port to a bus or the Master. Hold a card for its menu.")
                .font(.caption)
                .foregroundStyle(Studio.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Studio.bg0)
        }
        .background(Studio.bg0)
        .accessibilityIdentifier("flow")
        .confirmationDialog(dropped.map { "\($0.sourceName) to \($0.busName)" } ?? "",
                            isPresented: Binding(get: { dropped != nil }, set: { if !$0 { dropped = nil } }),
                            titleVisibility: .visible, presenting: dropped) { drop in
            if drop.canOutput {
                Button("Output to \(drop.busName)") { output(drop.sourceID, to: drop.busID) }
            }
            if drop.canSend {
                Button("Send to \(drop.busName)") { model.addSend(from: drop.sourceID, to: drop.busID) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Not routed", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refusal ?? "")
        }
    }

    private func graph(_ layout: FlowLayout, scale: CGFloat) -> some View {
        let hovered = dragging.flatMap { target(at: $0.location, from: $0.sourceID, in: layout) }
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for wire in layout.wires {
                    context.stroke(wire.path, with: .color(Studio.accent.opacity(wire.strength)),
                                   style: StrokeStyle(lineWidth: wire.send == nil ? 2.2 : 1.8, lineCap: .round))
                }
                if let dragging {                // the wire in the hand, from its port to the finger
                    var path = Path()
                    path.move(to: dragging.start)
                    path.addLine(to: dragging.location)
                    context.stroke(path, with: .color(Studio.accent),
                                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [6, 5]))
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
                FlowNodeCard(node: node, summary: summary(node), targeted: node.id == hovered)
                    .frame(width: FlowLayout.nodeWidth, height: FlowLayout.nodeHeight)
                    .contextMenu { menu(for: node) }
                    .accessibilityActions { actions(for: node) }
                    .position(x: node.frame.midX, y: node.frame.midY)
            }
            ForEach(layout.nodes.filter { $0.kind != "master" }) { node in
                portHandle(node, in: layout, scale: scale)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
    }

    /// Where a wire can be dragged from: the output port, a thumb's width on
    /// screen at any zoom, and no taller than a card and its gap.
    private func portHandle(_ node: FlowLayout.Node, in layout: FlowLayout, scale: CGFloat) -> some View {
        let port = CGPoint(x: node.frame.maxX + 5, y: node.frame.midY)
        let side = 44 / max(scale, 0.3)
        return Color.clear
            .frame(width: side, height: min(side, FlowLayout.nodeHeight + FlowLayout.rowGap))
            .contentShape(.rect)
            .position(port)
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in dragging = WireDrag(sourceID: node.id, start: port, location: value.location) }
                .onEnded { value in
                    dragging = nil
                    land(node.id, at: value.location, in: layout)
                })
            .accessibilityHidden(true)           // VoiceOver: the card's actions
    }

    /// The bus or Master card under a dragged wire's end, never its own.
    private func target(at point: CGPoint, from sourceID: String, in layout: FlowLayout) -> String? {
        layout.nodes.first { $0.kind != "track" && $0.id != sourceID && $0.frame.insetBy(dx: -8, dy: -8).contains(point) }?.id
    }

    /// A wire let go: on the Master, the output goes back there; on a bus, a
    /// bus moves its output (unless it would loop) and a track chooses.
    private func land(_ sourceID: String, at point: CGPoint, in layout: FlowLayout) {
        guard let source = routing.source(sourceID), let id = target(at: point, from: sourceID, in: layout) else { return }
        if id == RoutingState.master {
            output(sourceID, to: id)
            return
        }
        guard let bus = routing.source(id) else { return }
        if source.isBus {
            if let loop = routing.wouldLoop(sourceID, into: id) {
                refusal = "\(bus.name) would loop: \(loop.joined(separator: " → "))."
            } else {
                output(sourceID, to: id)
            }
            return
        }
        let sends = routing.sends(from: sourceID).contains { $0.busID == id }
        let canOutput = source.output != id
        guard canOutput || !sends else { return }
        dropped = WireDrop(sourceID: sourceID, sourceName: source.name, busID: id, busName: bus.name,
                           canOutput: canOutput, canSend: !sends)
    }

    private func output(_ sourceID: String, to output: String) {
        guard let source = routing.source(sourceID) else { return }
        model.setOutput(source, to: output)
    }

    /// A card's menu, as Studio's Flow keeps every edit in a context menu too:
    /// its output, a send to each bus it doesn't send to yet, and each send to take away.
    @ViewBuilder
    private func menu(for node: FlowLayout.Node) -> some View {
        if let source = routing.source(node.id) {
            Menu("Output: \(routing.outputName(of: source))") {
                Button { output(source.stripID, to: RoutingState.master) } label: {
                    choice("Master", on: source.output == RoutingState.master)
                }
                ForEach(routing.outputs(for: source)) { bus in
                    if let loop = source.isBus ? routing.wouldLoop(source.stripID, into: bus.stripID) : nil {
                        Button("\(bus.name), would loop: \(loop.joined(separator: " → "))") {}
                            .disabled(true)
                    } else {
                        Button { output(source.stripID, to: bus.stripID) } label: {
                            choice(bus.name, on: source.output == bus.stripID)
                        }
                    }
                }
            }
            if !source.isBus {
                let sent = Set(routing.sends(from: source.stripID).map(\.busID))
                let open = routing.buses.filter { !sent.contains($0.stripID) }
                if !open.isEmpty {
                    Menu("Send to") {
                        ForEach(open) { bus in
                            Button(bus.name) { model.addSend(from: source.stripID, to: bus.stripID) }
                        }
                    }
                }
                ForEach(routing.sends(from: source.stripID)) { send in
                    Button("Remove send to \(routing.source(send.busID)?.name ?? "the bus")", role: .destructive) {
                        model.removeSend(send)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func choice(_ name: String, on: Bool) -> some View {
        if on { Label(name, systemImage: "checkmark") } else { Text(name) }
    }

    /// The menu's edits as VoiceOver actions, without the dragging.
    @ViewBuilder
    private func actions(for node: FlowLayout.Node) -> some View {
        if let source = routing.source(node.id) {
            if source.output != RoutingState.master {
                Button("Output to Master") { output(source.stripID, to: RoutingState.master) }
            }
            ForEach(routing.outputs(for: source).filter { bus in
                source.output != bus.stripID && (!source.isBus || routing.wouldLoop(source.stripID, into: bus.stripID) == nil)
            }) { bus in
                Button("Output to \(bus.name)") { output(source.stripID, to: bus.stripID) }
            }
            if !source.isBus {
                let sent = Set(routing.sends(from: source.stripID).map(\.busID))
                ForEach(routing.buses.filter { !sent.contains($0.stripID) }) { bus in
                    Button("Send to \(bus.name)") { model.addSend(from: source.stripID, to: bus.stripID) }
                }
                ForEach(routing.sends(from: source.stripID)) { send in
                    Button("Remove send to \(routing.source(send.busID)?.name ?? "the bus")") { model.removeSend(send) }
                }
            }
        }
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

/// A wire in the hand: from its source's output port to the finger.
private struct WireDrag {
    let sourceID: String
    let start: CGPoint
    let location: CGPoint
}

/// A track's wire let go on a bus: Studio's plain drag makes it the output,
/// its Option drag a send; the phone asks which.
private struct WireDrop {
    let sourceID: String
    let sourceName: String
    let busID: String
    let busName: String
    let canOutput: Bool
    let canSend: Bool
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
    /// A dragged wire's end is over this card.
    var targeted = false

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
        .overlay(shape.strokeBorder(targeted ? Studio.accent : Studio.edge, lineWidth: targeted ? 2 : 1))
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
