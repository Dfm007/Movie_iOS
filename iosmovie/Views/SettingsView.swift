import SwiftUI

struct SettingsView: View {
    @State private var sites: [CMSSite] = CMSSite.all
    @State private var showAddSheet = false
    @State private var editingSite: CMSSite?
    @State private var showResetAlert = false

    var body: some View {
        List {
            Section {
                Text("目前仅支持苹果 CMS 采集站")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("自定义源") {
                ForEach(sites) { site in
                    Button {
                        editingSite = site
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(site.baseURL)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete(perform: deleteSites)
            }

            Section {
                Button("添加源") {
                    showAddSheet = true
                }
                Button("恢复默认源") {
                    showResetAlert = true
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("设置")
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
            }
            Button("否", role: .cancel) { }
        }
    }

    private func deleteSites(at offsets: IndexSet) {
        sites.remove(atOffsets: offsets)
        CMSSite.saveSites(sites)
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
                }
                Section("采集站地址") {
                    TextField("例如：https://example.com/api.php/provide/vod/from/xxx", text: $url)
                }
                Section {
                    Button("添加") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
                        onAdd(trimmedName, trimmedURL)
                        dismiss()
                    }
                }
            }
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
                }
                Section("采集站地址") {
                    TextField("采集站地址", text: $url)
                }
                Section {
                    Button("保存") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
                        onSave(trimmedName, trimmedURL)
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}