import RemoteKit
import SwiftUI

/// A strip's INSERTS, as Tabber Studio's mixer strip draws them
/// (ui/mixer_dock.py PluginChainWidget): a dot for a plug-in that plays, a
/// hollow one for a bypassed one, then "＋ Plugin". The zone keeps one height,
/// as Studio's does, so the faders stay level: a long chain shows its first
/// plug-in and "+k more…". Tap a plug-in for Studio's slot menu, as a sheet of
/// choices: Open on the computer, Bypass or Un-bypass, Remove (TR44).
struct InsertsZone: View {
    @Bindable var model: AppModel
    let strip: Strip
    /// The tallest zone on the mixer: every strip's is as tall, so the faders
    /// start level, as Studio's fixed INSERTS zone keeps them.
    var height: CGFloat = 0
    @State private var adding = false
    /// The plug-in whose menu is open.
    @State private var chosen: Insert?
    /// "+k more…": the whole chain, to choose one from.
    @State private var listingAll = false
    /// A row grows with the text size, and a long name wraps.
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat = 32

    static let spacing: CGFloat = 4

    var body: some View {
        let shown = strip.inserts.count > 2 ? Array(strip.inserts.prefix(1)) : strip.inserts
        VStack(spacing: Self.spacing) {
            ForEach(shown) { insert in
                Button { chosen = insert } label: { slot(insert) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(spoken(insert))
                    .accessibilityHint("Opens its window on the computer, or bypasses or removes it.")
                    .accessibilityIdentifier("insert-\(strip.name)-\(insert.name)")
            }
            if strip.inserts.count > 2 {
                Button { listingAll = true } label: {
                    row(Text("+\(strip.inserts.count - 1) more…").foregroundStyle(Studio.text2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All \(strip.inserts.count) plug-ins on \(strip.name)")
                .accessibilityIdentifier("inserts-more-\(strip.name)")
                .confirmationDialog("Plug-ins on \(strip.name)", isPresented: $listingAll, titleVisibility: .visible) {
                    ForEach(Array(strip.inserts.enumerated()), id: \.element.id) { index, insert in
                        Button(String(format: "%02d  %@%@", index + 1, insert.name, insert.bypassed ? "  BYP" : "")) {
                            chosen = insert
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            if model.loadingPlugin?.stripID == strip.id {
                row(HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Loading…").foregroundStyle(Studio.text2)
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading \(model.loadingPlugin?.name ?? "a plug-in") on the computer")
            } else {
                Button { adding = true } label: {
                    row(Text("＋ Plugin").foregroundStyle(Studio.text2), dashed: true)
                }
                .buttonStyle(.plain)
                .disabled(model.loadingPlugin != nil)
                .accessibilityLabel("Insert a plug-in on \(strip.name)")
                .accessibilityIdentifier("add-plugin-\(strip.name)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: InsertsHeight.self, value: proxy.size.height)
        })
        // Two plug-ins and "＋ Plugin", the rows Studio's strip shows before "+k more…".
        .frame(minHeight: max(height, rowHeight * 3 + Self.spacing * 2), alignment: .top)
        .sheet(isPresented: $adding) { InsertPluginSheet(model: model, strip: strip) }
        .confirmationDialog(chosen?.name ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible, presenting: chosen) { insert in
            Button("Open on the computer") { model.openInsert(insert, on: strip) }
            Button(insert.bypassed ? "Un-bypass" : "Bypass") { model.bypassInsert(insert, on: strip) }
            Button("Remove", role: .destructive) { model.removeInsert(insert, on: strip) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Studio's slot, one label: "● Name", or "○ Name" bypassed.
    private func slot(_ insert: Insert) -> some View {
        let dot = Text(insert.bypassed ? "○ " : "● ")
            .foregroundStyle(insert.autoBypassed ? Studio.record : (insert.bypassed ? Studio.text3 : Studio.accent))
        let name = Text(insert.name).foregroundStyle(insert.bypassed ? Studio.text2 : Studio.text1)
        return row(Text("\(dot)\(name)").fixedSize(horizontal: false, vertical: true))
            .opacity(model.pending.contains("remove-\(insert.id)") ? 0.4 : 1)
    }

    private func row(_ content: some View, dashed: Bool = false) -> some View {
        content
            .font(.caption2.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .padding(.vertical, 1)
            .padding(.horizontal, 6)
            .background(dashed ? Color.clear : Studio.bg0.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Studio.dashes, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))   // the "+ Bus" outline
                }
            }
            .contentShape(.rect)
    }

    private func spoken(_ insert: Insert) -> String {
        let state = insert.autoBypassed ? "bypassed by Tabber Studio, it took too long"
            : insert.bypassed ? "bypassed" : "on"
        return "\(insert.name) on \(strip.name), \(state)"
    }
}

/// Tabber Studio's Insert Plugin browser, for one strip (ui/plugin_browser_panel.py):
/// its Tabber Plugins and Plugins tabs, the format filter, and a search over
/// name, vendor, category, type and format. A greyed row says why it can't go
/// in. Tap a row to insert it at the end of the strip's chain.
struct InsertPluginSheet: View {
    enum Tab: String, CaseIterable { case tabber = "Tabber Plugins", plugins = "Plugins" }

    @Bindable var model: AppModel
    let strip: Strip
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.tabber
    @State private var format = "all"
    @State private var search = ""
    /// Why the last insert did not go in, in Tabber Studio's words; the browser stays open.
    @State private var refused: String?

    var body: some View {
        NavigationStack {
            List {
                if model.catalogLoading && model.catalog.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading the plug-ins on \(model.computerName)…").foregroundStyle(Studio.text2)
                    }
                    .listRowBackground(Studio.bg2)
                } else if rows.isEmpty {
                    Text(empty).foregroundStyle(Studio.text2).listRowBackground(Studio.bg2)
                }
                ForEach(rows) { row in
                    Button { insert(row) } label: { PluginRowLabel(row: row) }
                        .disabled(!row.available || model.loadingPlugin != nil)
                        .listRowBackground(Studio.bg2)
                        .accessibilityIdentifier("plugin-\(row.name)")
                }
            }
            .studioList()
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search plugins")
            .safeAreaInset(edge: .top, spacing: 0) { filters }
            .overlay(alignment: .bottom) { loading }
            .navigationTitle("Insert Plugin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("cancel")
                }
            }
        }
        .onAppear { model.loadCatalog() }
    }

    /// The browser's tabs and its All, VST3 and CLAP filter.
    private var filters: some View {
        VStack(spacing: 8) {
            Picker("Plugin source", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("plugin-source")
            Picker("Plugin format", selection: $format) {
                Text("All").tag("all")
                Text("VST3").tag("vst3")
                Text("CLAP").tag("clap")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("plugin-format")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Studio.bg1)
    }

    @ViewBuilder
    private var loading: some View {
        if let refused, model.loadingPlugin == nil {
            Text(refused)
                .font(.subheadline)
                .foregroundStyle(Studio.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .studioCard()
                .padding(16)
                .accessibilityIdentifier("plugin-refused")
        } else if let loading = model.loadingPlugin, loading.stripID == strip.id {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading \(loading.name) on \(model.computerName)…")
                    .font(.subheadline)
                    .foregroundStyle(Studio.text1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .studioCard()
            .padding(16)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plugin-loading")
        }
    }

    private var empty: String {
        if !search.isEmpty { return "No plug-in matches \u{201C}\(search)\u{201D}." }
        return tab == .tabber ? "No Tabber plug-ins on \(model.computerName)."
            : "No other plug-ins on \(model.computerName). Tabber Studio finds them when it scans for plug-ins."
    }

    /// The browser's rows for this tab, format and search, in its order.
    private var rows: [PluginRow] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return model.catalog.filter { row in
            row.tabber == (tab == .tabber) && (format == "all" || row.format == format)
                && (query.isEmpty || [row.name, row.vendor, row.category, row.typeLabel, row.formatLabel]
                    .contains { $0.lowercased().contains(query) })
        }
    }

    private func insert(_ row: PluginRow) {
        refused = nil
        model.insertPlugin(row, on: strip) { inserted in
            if inserted { dismiss() } else { refused = model.problem }
        }
    }
}

/// One row of the browser: the name, its vendor and category, then its type and format.
private struct PluginRowLabel: View {
    let row: PluginRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(row.available ? Studio.text1 : Studio.text3)
                Text(row.available ? "\(row.vendor), \(row.category)" : (row.reason ?? "Unavailable"))
                    .font(.footnote)
                    .foregroundStyle(row.available ? Studio.text2 : Studio.text3)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(row.typeLabel)
                Text(row.formatLabel)
            }
            .font(.caption)
            .foregroundStyle(Studio.text2)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

/// The tallest INSERTS zone's natural height, so the mixer can give every strip that height.
struct InsertsHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
