import SwiftUI

struct SettingsView: View {
    @State private var sites: [CMSSite] = CMSSite.all
    @State private var defaultSiteID: String = CMSSite.selectedDefaultSite.id
    @State private var showAddSheet = false
    @State private var editingSite: CMSSite?
    @State private var showResetAlert = false
    @StateObject private var latencyManager = SiteLatencyManager.shared
    @AppStorage("appearance_mode") private var appearanceMode = "system"
    @State private var wifiOnlyDownload = DownloadPreferences.wifiOnly

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .foregroundColor(AppTheme.accentSecondary)
                    Text("目前仅支持苹果 CMS 采集站")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }

            Section {
                Picker("默认源", selection: $defaultSiteID) {
                    ForEach(sites) { site in
                        SiteLatencyLabel(site: site, latencyManager: latencyManager)
                            .tag(site.id)
                    }
                }
                .onChange(of: defaultSiteID) { newID in
                    CMSSite.saveDefaultSiteID(newID)
                    NotificationCenter.default.post(name: .defaultSourceDidChange, object: nil)
                }
                .listRowBackground(AppTheme.surface)

                Text("主页只会显示默认源采集到的影视")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
            } header: {
                Label("默认源", systemImage: "star.fill")
            }

            Section {
                ForEach(sites) { site in
                    Button {
                        editingSite = site
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundColor(AppTheme.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                SiteLatencyLabel(site: site, latencyManager: latencyManager)
                                Text(site.baseURL)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    .listRowBackground(AppTheme.surface)
                }
                .onDelete(perform: deleteSites)
            } header: {
                Label("自定义源", systemImage: "square.stack.3d.up")
            }

            Section {
                Button {
                    Task { await latencyManager.measureAll(sites: sites) }
                } label: {
                    Label("重新测速", systemImage: "speedometer")
                        .foregroundColor(AppTheme.textPrimary)
                }
                .listRowBackground(AppTheme.surface)

                Button {
                    showAddSheet = true
                } label: {
                    Label("添加源", systemImage: "plus.circle")
                        .foregroundColor(AppTheme.accent)
                }
                .listRowBackground(AppTheme.surface)

                Button {
                    showResetAlert = true
                } label: {
                    Label("恢复默认源", systemImage: "arrow.counterclockwise")
                        .foregroundColor(AppTheme.danger)
                }
                .listRowBackground(AppTheme.surface)
            }

            Section {
                Picker("外观", selection: $appearanceMode) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
                .tint(AppTheme.accent)
                .listRowBackground(AppTheme.surface)
            } header: {
                Label("外观", systemImage: "circle.lefthalf.filled")
            }

            Section {
                Toggle(isOn: $wifiOnlyDownload) {
                    Label("仅 Wi-Fi 下载", systemImage: "wifi")
                        .foregroundColor(AppTheme.textPrimary)
                }
                .tint(AppTheme.accent)
                .onChange(of: wifiOnlyDownload) { newValue in
                    DownloadPreferences.wifiOnly = newValue
                    // 刚开启时如果正走移动网络，立即暂停正在进行的下载
                    DownloadManager.shared.enforceWifiOnlyPolicy()
                }
                .listRowBackground(AppTheme.surface)

                Text("开启后，移动网络下不会开始新下载，下载中的任务会自动暂停。")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
            } header: {
                Label("下载", systemImage: "arrow.down.circle")
            }

            Section {
                NavigationLink(destination: FeedbackView()) {
                    Label("意见反馈", systemImage: "bubble.left.and.bubble.right")
                        .foregroundColor(AppTheme.textPrimary)
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .background(AppTheme.background.ignoresSafeArea())
        .tint(AppTheme.accent)
        .navigationTitle("设置")
        .task {
            sites = CMSSite.all
            defaultSiteID = CMSSite.selectedDefaultSite.id
            await latencyManager.measureAll(sites: sites)
        }
        .sheet(isPresented: $showAddSheet) {
            AddSiteView { name, url in
                let newSite = CMSSite(id: UUID().uuidString, name: name, baseURL: url)
                sites.append(newSite)
                CMSSite.saveSites(sites)
                showAddSheet = false
            }
        }
        .sheet(item: $editingSite) { site in
            EditSiteView(site: site) { name, url in
                if let index = sites.firstIndex(where: { $0.id == site.id }) {
                    sites[index] = CMSSite(id: site.id, name: name, baseURL: url)
                    CMSSite.saveSites(sites)
                }
            }
        }
        .alert("确认恢复默认源吗？", isPresented: $showResetAlert) {
            Button("是", role: .destructive) {
                CMSSite.resetToBuiltIn()
                sites = CMSSite.all
                defaultSiteID = CMSSite.selectedDefaultSite.id
            }
            Button("否", role: .cancel) { }
        }
    }

    private func deleteSites(at offsets: IndexSet) {
        sites.remove(atOffsets: offsets)
        CMSSite.saveSites(sites)
        if !sites.contains(where: { $0.id == defaultSiteID }) {
            defaultSiteID = sites.first?.id ?? ""
            CMSSite.saveDefaultSiteID(defaultSiteID)
        }
    }
}

private struct SiteLatencyLabel: View {
    let site: CMSSite
    @ObservedObject var latencyManager: SiteLatencyManager

    var body: some View {
        HStack(spacing: 8) {
            Text(site.name)
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            Text(latencyManager.latencyText(for: site))
                .font(.caption.weight(.semibold))
                .foregroundColor(latencyManager.color(for: site))
        }
    }
}

struct AddSiteView: View {
    var onAdd: (String, String) -> Void

    @State private var name = ""
    @State private var url = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("源名称") {
                    TextField("例如：新源", text: $name)
                        .foregroundColor(AppTheme.textPrimary)
                        .listRowBackground(AppTheme.surface)
                }
                Section("采集站地址") {
                    TextField("例如：https://example.com/api.php/provide/vod/from/xxx", text: $url)
                        .foregroundColor(AppTheme.textPrimary)
                        .listRowBackground(AppTheme.surface)
                }
                Section {
                    Button("添加") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
                        onAdd(trimmedName, trimmedURL)
                        dismiss()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .listRowBackground(Color.clear)
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .tint(AppTheme.accent)
            .navigationTitle("添加源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct EditSiteView: View {
    let site: CMSSite
    var onSave: (String, String) -> Void

    @State private var name: String
    @State private var url: String
    @Environment(\.dismiss) private var dismiss

    init(site: CMSSite, onSave: @escaping (String, String) -> Void) {
        self.site = site
        self.onSave = onSave
        _name = State(initialValue: site.name)
        _url = State(initialValue: site.baseURL)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("源名称") {
                    TextField("源名称", text: $name)
                        .foregroundColor(AppTheme.textPrimary)
                        .listRowBackground(AppTheme.surface)
                }
                Section("采集站地址") {
                    TextField("采集站地址", text: $url)
                        .foregroundColor(AppTheme.textPrimary)
                        .listRowBackground(AppTheme.surface)
                }
                Section {
                    Button("保存") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
                        onSave(trimmedName, trimmedURL)
                        dismiss()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .listRowBackground(Color.clear)
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .tint(AppTheme.accent)
            .navigationTitle("编辑源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
