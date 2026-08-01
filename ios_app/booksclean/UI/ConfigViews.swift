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
                            .fsFont(.subheadline).fontWeight(.medium)
                        Text("类型: \(c.fileTypes) · \(c.recursive ? "递归" : "仅当前目录") · 最小\(c.minSizeKb)KB")
                            .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
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

/// 内置可勾选的文件类型（与安卓 BUILTIN_TYPES 保持一致）。
let BUILTIN_FILE_TYPES = ["txt", "epub", "pdf", "mobi", "azw3", "doc", "docx"]

struct ConfigEditView: View {
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    let configId: Int64

    @State private var name = ""
    @State private var folderName = ""
    @State private var folderUri = ""
    @State private var selectedTypes: Set<String> = ["txt"]
    @State private var customType = ""
    @State private var minSizeText = "0"
    @State private var recursive = true
    @State private var exactHash = false
    @State private var excludedNames: [String] = []
    @State private var scanMode = "quick"
    @State private var showingFolderPicker = false
    @State private var showingExcludePicker = false

    var body: some View {
        Form {
            Section("配置名称") {
                TextField("如：我的小说库", text: $name)
            }

            Section("扫描文件夹路径") {
                Text(folderName.isEmpty ? "未选择文件夹" : folderName)
                    .fsFont(.subheadline)
                    .foregroundColor(folderName.isEmpty ? .fsSecondaryLabel : .primary)
                    .lineLimit(2)
                Button {
                    showingFolderPicker = true
                } label: {
                    Label(folderUri.isEmpty ? "选择文件夹" : "更换文件夹", systemImage: "folder")
                }
            }

            Section("文件类型") {
                ForEach(BUILTIN_FILE_TYPES, id: \.self) { t in
                    Button {
                        if selectedTypes.contains(t) { selectedTypes.remove(t) } else { selectedTypes.insert(t) }
                    } label: {
                        HStack {
                            Image(systemName: selectedTypes.contains(t) ? "checkmark.square.fill" : "square")
                                .foregroundColor(selectedTypes.contains(t) ? .fsPrimary : .fsSecondaryLabel)
                            Text(t).foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                TextField("自定义类型（逗号分隔，如 csv）", text: $customType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section {
                if excludedNames.isEmpty {
                    Text("未设置排除文件夹，扫描将包含全部子目录。")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                } else {
                    ForEach(excludedNames, id: \.self) { n in
                        HStack {
                            Text(n).fsFont(.subheadline).lineLimit(1)
                            Spacer()
                            Button {
                                excludedNames.removeAll { $0 == n }
                            } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.fsSecondaryLabel) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                Button { showingExcludePicker = true } label: { Label("添加排除文件夹", systemImage: "plus") }
            } header: {
                Text("排除的文件夹")
            } footer: {
                Text("按文件夹「名称」匹配，扫描时会跳过同名目录。")
            }

            Section("最小文件大小 (KB)") {
                TextField("0", text: $minSizeText)
                    .keyboardType(.numberPad)
                    .onChange(of: minSizeText) { v in
                        minSizeText = v.filter { $0.isNumber }
                    }
            }

            Section {
                Picker("扫描模式", selection: $scanMode) {
                    Text("快速").tag("quick")
                    Text("深度").tag("deep")
                }
                .pickerStyle(.segmented)
                Text(scanMode == "quick"
                     ? "快速：只根据文件名解析书名/作者/进度/来源，速度最快，不读取文件内容。"
                     : "深度：额外读取文件内容识别编码并可计算内容指纹，更准确但耗时明显更长。")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                if scanMode == "deep" {
                    Toggle("精确内容去重（计算内容指纹）", isOn: $exactHash)
                }
            } header: {
                Text("扫描模式")
            }

            Section {
                Toggle("递归子目录", isOn: $recursive)
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadIfEdit() }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPicker { url in
                showingFolderPicker = false
                folderUri = makeBookmark(url) ?? ""
                folderName = url.lastPathComponent
                if name.isEmpty { name = url.lastPathComponent }
            }
        }
        .sheet(isPresented: $showingExcludePicker) {
            FolderPicker { url in
                showingExcludePicker = false
                let n = url.lastPathComponent.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty && !excludedNames.contains(n) { excludedNames.append(n) }
            }
        }
    }

    private func loadIfEdit() {
        if configId > 0, let c = FileRepository.shared.getScanConfig(configId) {
            name = c.name; folderName = c.folderName; folderUri = c.folderUri
            selectedTypes = Set(c.fileTypes.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            if selectedTypes.isEmpty { selectedTypes = ["txt"] }
            excludedNames = c.excludedFolders.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            minSizeText = String(c.minSizeKb)
            recursive = c.recursive
            exactHash = c.exactHash
            scanMode = c.scanMode.isEmpty ? "quick" : c.scanMode
        } else if configId == 0 {
            // 新建：用设置页的全局默认值预填（对齐安卓）
            let prefs = Preferences.shared
            let types = Set(prefs.scanFileTypes.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            selectedTypes = types.isEmpty ? ["txt"] : types
            minSizeText = String(prefs.minFileSizeKb)
            recursive = prefs.recursive
        }
    }

    private func buildConfig() -> ScanConfig {
        let extra = customType.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var all = Array(selectedTypes) + extra
        all = Array(Set(all)).sorted()
        var c = ScanConfig()
        c.id = configId
        c.name = name.trimmingCharacters(in: .whitespaces)
        c.folderName = folderName
        c.folderUri = folderUri
        c.fileTypes = all.isEmpty ? "txt" : all.joined(separator: ",")
        c.minSizeKb = Int(minSizeText) ?? 0
        c.recursive = recursive
        c.exactHash = exactHash
        c.excludedFolders = excludedNames.joined(separator: ",")
        c.scanMode = scanMode
        return c
    }
}
