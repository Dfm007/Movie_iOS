import SwiftUI

struct SettingsView: View {
    @State private var sites: [CMSSite] = CMSSite.all
    @State private var showAddSheet = false

    var body: some View {
        List {
            Section {
                Text("目前仅支持苹果 CMS 采集站")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("自定义源") {
                ForEach(sites) { site in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(site.name)
                            .font(.body)
                        Text(site.baseURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .onDelete(perform: deleteSites)
            }

            Section {
                Button("添加源") {
                    showAddSheet = true
                }
                Button("恢复默认源") {
                    CMSSite.resetToBuiltIn()
                    sites = CMSSite.all
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
