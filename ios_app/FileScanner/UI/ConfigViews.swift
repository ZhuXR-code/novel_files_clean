import SwiftUI

struct ConfigListView: View {
    @EnvironmentObject var router: Router
    @State private var configs: [ScanConfig] = []

    var body: some View {
        List {
            ForEach(configs) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.name.isEmpty ? (c.folderName.isEmpty ? "未命名配置" : c.folderName) : c.name)
                            .font(.subheadline).fontWeight(.medium)
                        Text("类型: \(c.fileTypes) · \(c.recursive ? "递归" : "仅当前目录") · 最小\(c.minSizeKb)KB")
                            .font(.caption).foregroundColor(.fsSecondaryLabel)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
                }
                .contentShape(Rectangle())
                .onTapGesture { router.navigate(.configEdit(id: c.id)) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        FileRepository.shared.deleteScanConfig(c.id)
                        reload()
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("扫描配置")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { router.navigate(.configEdit(id: 0)) } label: { Image(systemName: "plus") }
            }
        }
        .onAppear { reload() }
    }

    private func reload() { configs = FileRepository.shared.getScanConfigs() }
}

struct ConfigEditView: View {
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    let configId: Int64

    @State private var name = ""
    @State private var folderName = ""
    @State private var folderUri = ""
    @State private var fileTypes = "txt"
    @State private var minSizeKb = 0
    @State private var recursive = true
    @State private var exactHash = false
    @State private var excludedFolders = ""
    @State private var scanMode = "quick"
    @State private var showingFolderPicker = false

    var body: some View {
        Form {
            Section("基本") {
                TextField("配置名称", text: $name)
                Button {
                    showingFolderPicker = true
                } label: {
                    HStack {
                        Text("选择文件夹")
                        Spacer()
                        Text(folderName.isEmpty ? "未选择" : folderName)
                            .foregroundColor(.fsSecondaryLabel)
                    }
                }
            }
            Section("文件类型") {
                TextField("扩展名，逗号分隔 (如 txt,md)", text: $fileTypes)
                Stepper("最小文件大小: \(minSizeKb) KB", value: $minSizeKb, in: 0...102400)
                Toggle("递归子目录", isOn: $recursive)
            }
            Section("解析模式") {
                Picker("扫描模式", selection: $scanMode) {
                    Text("快速（仅文件名解析）").tag("quick")
                    Text("深度（读取内容识别编码）").tag("deep")
                }
                Toggle("精确内容去重（计算内容指纹）", isOn: $exactHash)
            }
            Section("排除") {
                TextField("排除文件夹名（逗号分隔）", text: $excludedFolders)
            }
            Section {
                Button {
                    let saved = buildConfig()
                    let id = FileRepository.shared.saveScanConfig(saved)
                    let cfg = FileRepository.shared.getScanConfig(id) ?? saved
                    beginScan(cfg)
                } label: { Text("保存并开始扫描").frame(maxWidth: .infinity) }
                .disabled(folderUri.isEmpty)
            }
        }
        .navigationTitle(configId > 0 ? "编辑配置" : "新建配置")
        .onAppear { loadIfEdit() }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPicker { url in
                showingFolderPicker = false
                folderUri = makeBookmark(url) ?? ""
                folderName = url.lastPathComponent
                if name.isEmpty { name = url.lastPathComponent }
            }
        }
    }

    private func loadIfEdit() {
        guard configId > 0, let c = FileRepository.shared.getScanConfig(configId) else { return }
        name = c.name; folderName = c.folderName; folderUri = c.folderUri
        fileTypes = c.fileTypes; minSizeKb = c.minSizeKb; recursive = c.recursive
        exactHash = c.exactHash; excludedFolders = c.excludedFolders; scanMode = c.scanMode
    }

    private func buildConfig() -> ScanConfig {
        var c = ScanConfig()
        c.id = configId
        c.name = name
        c.folderName = folderName
        c.folderUri = folderUri
        c.fileTypes = fileTypes
        c.minSizeKb = minSizeKb
        c.recursive = recursive
        c.exactHash = exactHash
        c.excludedFolders = excludedFolders
        c.scanMode = scanMode
        return c
    }
}
