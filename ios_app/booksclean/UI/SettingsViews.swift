import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Preferences
    @State private var showExportResult = false
    @State private var exportPath: String = ""
    @State private var showClearConfirm = false

    var body: some View {
        List {
            Section("重复清理") {
                row("勾选重复规则") { router.navigate(.dupRule) }
            }
            Section("文件处理") {
                row("关键词替换规则") { router.navigate(.keywordReplace) }
            }
            Section("日志") {
                row("操作日志") { router.navigate(.logViewer) }
            }
            Section("显示偏好") {
                Picker("主题", selection: $prefs.themeMode) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
            }
            Section("默认扫描参数") {
                TextField("默认文件类型（逗号分隔）", text: $prefs.scanFileTypes)
                Stepper("默认最小大小: \(prefs.minFileSizeKb) KB", value: $prefs.minFileSizeKb, in: 0...102400)
                Toggle("默认递归子目录", isOn: $prefs.recursive)
            }
            Section("合集过滤默认") {
                Stepper("最小数量: \(prefs.groupMinCount)", value: $prefs.groupMinCount, in: 0...1000)
                Toggle("限制最大数量", isOn: Binding(get: { prefs.groupMaxCount >= 0 }, set: { v in prefs.groupMaxCount = v ? 500 : -1 }))
                if prefs.groupMaxCount >= 0 {
                    Stepper("最大数量: \(prefs.groupMaxCount)", value: $prefs.groupMaxCount, in: 0...100000)
                }
                TextField("排除书名（逗号分隔）", text: $prefs.groupExcludeNames)
            }
            // 对齐安卓「数据与备份」：导出已标记 / 清空数据
            Section("数据与备份") {
                Button {
                    if let p = FileRepository.shared.exportMarkedFiles() {
                        exportPath = p; showExportResult = true
                    } else {
                        exportPath = ""; showExportResult = true
                    }
                } label: { Label("导出已标记文件清单", systemImage: "square.and.arrow.up") }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: { Label("清空全部数据", systemImage: "trash.fill") }
            }
            Section {
                Button { router.navigate(.help) } label: { Label("使用帮助", systemImage: "questionmark.circle") }
                Button { router.navigate(.privacy) } label: { Label("隐私协议", systemImage: "hand.raised.fill") }
                Button { router.navigate(.about) } label: { Label("关于", systemImage: "info.circle") }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("导出结果", isPresented: $showExportResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportPath.isEmpty ? "当前没有已标记的文件。" : "已导出到：\n\(exportPath)")
        }
        .alert("清空全部数据", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                FileRepository.shared.clearAllData()
            }
        } message: {
            Text("将删除所有扫描文库、文件记录、规则与日志，且无法恢复。确定继续？")
        }
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
            }
        }
    }
}

// MARK: - 勾选重复规则（对齐安卓 DupRuleConfigScreen）

/// 一条匹配条件：对某个字段写正则。多条之间为「且」关系。
struct DupPatternItem: Identifiable, Equatable {
    let id = UUID()
    var field: String = "file_name"
    var regex: String = ""
}

/// 可选的处理项（字段），与安卓 FIELD_OPTIONS 完全一致。
let DUP_FIELD_OPTIONS: [(String, String)] = [
    ("file_name", "文件名"),
    ("novel_name", "小说名"),
    ("author", "作者"),
    ("progress", "进度"),
    ("source", "来源"),
    ("file_size", "文件大小(字节)"),
    ("created_date", "创建日期")
]

func dupFieldLabel(_ key: String) -> String {
    DUP_FIELD_OPTIONS.first { $0.0 == key }?.1 ?? key
}

/// 把安卓旧格式的 op+value 尽量转成正则，兼容已有自定义规则。
private func oldOpToRegex(op: String, value: String) -> String {
    if value.isEmpty { return "" }
    let esc = NSRegularExpression.escapedPattern(for: value)
    switch op {
    case "contains": return esc
    case "not_contains", "neq": return "(?s)^(?:(?!\(esc)).)*$"
    case "starts_with": return "^\(esc)"
    case "ends_with": return "\(esc)$"
    case "eq": return "^\(esc)$"
    case "regex": return value
    default: return ""
    }
}

func parseDupPatterns(_ json: String?) -> [DupPatternItem] {
    guard let json, !json.isEmpty, json != "[]",
          let data = json.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return arr.map { obj in
        let field = obj["field"] as? String ?? "file_name"
        let regex: String
        if let r = obj["regex"] as? String {
            regex = r
        } else {
            regex = oldOpToRegex(op: obj["op"] as? String ?? "eq", value: obj["value"] as? String ?? "")
        }
        return DupPatternItem(field: field, regex: regex)
    }
}

func serializeDupPatterns(_ patterns: [DupPatternItem]) -> String {
    let arr = patterns.filter { !$0.regex.isEmpty }.map { ["field": $0.field, "regex": $0.regex] }
    guard !arr.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: arr),
          let s = String(data: data, encoding: .utf8) else { return "[]" }
    return s
}

struct DupRuleView: View {
    @EnvironmentObject var router: Router
    @State private var builtins: [DupRuleConfig] = []
    @State private var userRules: [DupRuleConfig] = []
    @State private var editing: DupRuleConfig? = nil
    @State private var showEditor = false

    var body: some View {
        List {
            Section {
                Text("选择「勾选重复」时应用的检测规则。内置规则不可删除；自定义规则可增删改。自定义规则：选择要处理的项并填写正则表达式，命中后执行对应动作。")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
            }

            if !builtins.isEmpty {
                Section("内置规则（不可删除）") {
                    ForEach($builtins) { $c in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text($c.wrappedValue.ruleName).fsFont(.subheadline).fontWeight(.medium)
                                    Text("内置").fsFont(.caption2).fontWeight(.bold).foregroundColor(.fsPrimary)
                                }
                                Text($c.wrappedValue.desc).fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { $c.wrappedValue.enabled }, set: { v in
                                $c.wrappedValue.enabled = v
                                FileRepository.shared.setDupRuleEnabled(key: $c.wrappedValue.ruleKey, enabled: v)
                            })).labelsHidden()
                        }
                    }
                }
            }

            Section("自定义规则") {
                if userRules.isEmpty {
                    Text("暂无自定义规则").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }
                ForEach($userRules) { $c in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text($c.wrappedValue.ruleName.isEmpty ? "(未命名)" : $c.wrappedValue.ruleName)
                                    .fsFont(.subheadline).fontWeight(.medium)
                                Text("自定义").fsFont(.caption2).fontWeight(.bold).foregroundColor(.orange)
                            }
                            Text("\($c.wrappedValue.action == "protect" ? "🛡️保护" : "✓勾选") - \(patternSummary($c.wrappedValue.conditions))")
                                .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                        }
                        Spacer()
                        Button {
                            editing = $c.wrappedValue
                            showEditor = true
                        } label: { Image(systemName: "pencil").foregroundColor(.fsSecondaryLabel) }
                            .buttonStyle(.borderless)
                        Toggle("", isOn: Binding(get: { $c.wrappedValue.enabled }, set: { v in
                            $c.wrappedValue.enabled = v
                            var copy = $c.wrappedValue; copy.enabled = v
                            _ = FileRepository.shared.saveDupRuleConfig(copy)
                        })).labelsHidden()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            FileRepository.shared.deleteDupRuleConfig($c.wrappedValue.id)
                            reload()
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
                Button {
                    editing = nil
                    showEditor = true
                } label: { Label("添加自定义规则", systemImage: "plus") }
            }

            Section {
                Text("提示：修改后立即生效，下次执行「勾选重复」时按新规则执行。")
                    .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
            }
        }
        .navigationTitle("勾选重复规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editing = nil
                    showEditor = true
                } label: { Image(systemName: "plus") }
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showEditor) {
            DupRuleEditorSheet(original: editing) { reload() }
        }
    }

    private func patternSummary(_ json: String?) -> String {
        let pats = parseDupPatterns(json)
        if pats.isEmpty { return "无条件" }
        return pats.map { "\(dupFieldLabel($0.field)) ~ \($0.regex)" }.joined(separator: " 且 ")
    }

    private func reload() {
        let all = FileRepository.shared.getDupRuleConfigs()
        builtins = all.filter { $0.isBuiltin }
        userRules = all.filter { !$0.isBuiltin }
    }
}

/// 自定义规则编辑器（新增/编辑通用，含多条件与正则测试，对齐安卓 UserRuleDialog）。
struct DupRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let original: DupRuleConfig?
    let onSaved: () -> Void

    @State private var name = ""
    @State private var desc = ""
    @State private var action = "check"
    @State private var patterns: [DupPatternItem] = [DupPatternItem()]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("规则名称", text: $name)
                    TextField("备注说明（可选）", text: $desc)
                }
                Section("动作") {
                    Picker("动作", selection: $action) {
                        Text("勾选").tag("check")
                        Text("🛡️ 保护").tag("protect")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("匹配条件：对所选「项」的内容用正则匹配，以下每条都需满足才命中本规则。")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                    ForEach($patterns) { $p in
                        DupPatternEditor(pattern: $p, canRemove: patterns.count > 1) {
                            patterns.removeAll { $0.id == $p.wrappedValue.id }
                        }
                    }
                    Button { patterns.append(DupPatternItem()) } label: { Text("＋ 添加匹配项") }
                }
            }
            .navigationTitle(original == nil ? "添加自定义规则" : "编辑自定义规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        guard let o = original else { return }
        name = o.ruleName
        desc = o.desc
        action = o.action ?? "check"
        let pats = parseDupPatterns(o.conditions)
        patterns = pats.isEmpty ? [DupPatternItem()] : pats
    }

    private func save() {
        var c = original ?? DupRuleConfig()
        c.ruleName = name.trimmingCharacters(in: .whitespaces)
        c.desc = desc
        c.action = action
        c.conditions = serializeDupPatterns(patterns)
        c.isBuiltin = false
        if original == nil { c.enabled = true }
        _ = FileRepository.shared.saveDupRuleConfig(c)
        onSaved()
        dismiss()
    }
}

/// 单条匹配项：字段下拉 + 正则输入 + 正则校验 + 样例测试（对齐安卓 PatternRow）。
struct DupPatternEditor: View {
    @Binding var pattern: DupPatternItem
    let canRemove: Bool
    let onRemove: () -> Void

    @State private var testInput = ""
    @State private var testResult: Bool? = nil

    private var regexError: String? {
        if pattern.regex.isEmpty { return nil }
        do { _ = try NSRegularExpression(pattern: pattern.regex); return nil }
        catch { return error.localizedDescription }
    }
    private var canRun: Bool {
        !pattern.regex.isEmpty && !testInput.isEmpty && regexError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("如果").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                Picker("", selection: $pattern.field) {
                    ForEach(DUP_FIELD_OPTIONS, id: \.0) { opt in
                        Text(opt.1).tag(opt.0)
                    }
                }
                .labelsHidden()
                Spacer()
                if canRemove {
                    Button { onRemove() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.fsSecondaryLabel) }
                        .buttonStyle(.borderless)
                }
            }
            TextField("正则表达式", text: $pattern.regex)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: pattern.regex) { _ in testResult = nil }
            if let err = regexError {
                Text("正则无效：\(err)").fsFont(.caption2).foregroundColor(.red)
            }
            Text("示例：文件名含「水印」→ 水印；以「完结」开头 → ^完结；作者等于张三 → ^张三$")
                .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)

            Text("测试本正则（可选）：输入一段样例文本，点「运行测试」查看是否命中")
                .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
            TextField("例如：某某小说_水印.txt", text: $testInput)
                .autocorrectionDisabled()
                .onChange(of: testInput) { _ in testResult = nil }
            HStack(spacing: 10) {
                Button("运行测试") {
                    guard let re = try? NSRegularExpression(pattern: pattern.regex) else { testResult = nil; return }
                    let range = NSRange(testInput.startIndex..., in: testInput)
                    testResult = re.firstMatch(in: testInput, range: range) != nil
                }
                .buttonStyle(.bordered)
                .disabled(!canRun)
                switch testResult {
                case nil:
                    Text(canRun ? "（未运行）" : "（请先填正则与样例文本）")
                        .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                case .some(true):
                    Text("✓ 命中").fsFont(.caption).fontWeight(.medium).foregroundColor(.fsPrimary)
                case .some(false):
                    Text("✗ 未命中").fsFont(.caption).fontWeight(.medium).foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 关键词替换规则（对齐安卓 KeywordReplaceScreen：作用域分段 + 编辑 + 排序 + 测试 + 恢复默认）
struct KeywordReplaceView: View {
    @State private var rules: [KeywordReplaceRule] = []
    @State private var scope = KeywordReplace.SCOPE_SCAN
    @State private var editing: KeywordReplaceRule? = nil
    @State private var showEditor = false
    @State private var showRestoreConfirm = false
    @State private var showBatch = false
    @State private var batchMode = "remove" // remove | replace
    @State private var batchText = ""
    @State private var batchEnabled = true
    @State private var testText = ""
    @State private var searchOpen = false
    @State private var searchText = ""
    /// nil=无待确认操作；true=批量启用；false=批量不启用
    @State private var batchEnableTarget: Bool? = nil

    private var scoped: [KeywordReplaceRule] {
        rules.filter { $0.scope == scope }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 按搜索词过滤后的规则（匹配查找 / 替换内容，忽略大小写）
    private var filtered: [KeywordReplaceRule] {
        let kw = searchText.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return scoped }
        return scoped.filter {
            $0.pattern.localizedCaseInsensitiveContains(kw) ||
            $0.replacement.localizedCaseInsensitiveContains(kw)
        }
    }

    /// 实时预览：按当前作用域的启用规则依次替换。
    private var testOutput: String {
        guard !testText.isEmpty else { return "" }
        return KeywordReplace.applyRules(testText, scoped.filter { $0.enabled }) ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("作用域", selection: $scope) {
                Text("扫描阶段").tag(KeywordReplace.SCOPE_SCAN)
                Text("解析阶段").tag(KeywordReplace.SCOPE_PARSE)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            List {
                Section {
                    Text(scope == KeywordReplace.SCOPE_SCAN
                         ? "扫描阶段：在文件被扫描入库时，先对「文件名」做替换，再进行解析。"
                         : "解析阶段：在解析出「书名 / 作者 / 进度 / 来源」之后，对这些字段做替换。")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                    Text("规则按顺序依次执行，前一条的结果作为后一条的输入；替换内容留空表示删除。")
                        .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                }

                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            searchOpen.toggle()
                            if !searchOpen { searchText = "" }
                        }
                    } label: {
                        HStack {
                            Label(searchOpen ? "收起搜索" : "搜索规则", systemImage: "magnifyingglass")
                                .fsFont(.subheadline).foregroundColor(.fsSecondaryLabel)
                            Spacer()
                            Image(systemName: searchOpen ? "chevron.up" : "chevron.down")
                                .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                        }
                    }
                    if searchOpen {
                        TextField("按 查找 / 替换 内容过滤规则…", text: $searchText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section("规则（\(filtered.count) 条）") {
                    if filtered.isEmpty {
                        Text(searchText.trimmingCharacters(in: .whitespaces).isEmpty
                             ? "当前作用域暂无规则" : "无匹配规则")
                            .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                    } else {
                        // 批量启用 / 不启用：仅作用于当前列表（搜索命中）的规则，直接写库
                        HStack(spacing: 8) {
                            Text("已启用 \(filtered.filter { $0.enabled }.count) / 未启用 \(filtered.filter { !$0.enabled }.count)")
                                .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                            Spacer()
                            Button("批量启用") { batchEnableTarget = true }
                                .buttonStyle(.borderless).fsFont(.caption)
                            Button("批量不启用") { batchEnableTarget = false }
                                .buttonStyle(.borderless).fsFont(.caption)
                                .foregroundColor(.fsSecondaryLabel)
                        }
                    }
                    ForEach(filtered) { r in
                        HStack(alignment: .top) {
                            Text("\(r.sortOrder)")
                                .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                                .frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.pattern).fsFont(.subheadline).fontWeight(.medium)
                                Text("→ \(r.replacement.isEmpty ? "（删除）" : r.replacement)")
                                    .fsFont(.caption2)
                                    .foregroundColor(r.replacement.isEmpty ? .red : .fsSecondaryLabel)
                            }
                            Spacer()
                            Button { move(r, up: true) } label: { Image(systemName: "arrow.up") }
                                .buttonStyle(.borderless).foregroundColor(.fsSecondaryLabel)
                                .disabled(scoped.first?.id == r.id)
                            Button { move(r, up: false) } label: { Image(systemName: "arrow.down") }
                                .buttonStyle(.borderless).foregroundColor(.fsSecondaryLabel)
                                .disabled(scoped.last?.id == r.id)
                            Button { editing = r; showEditor = true } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless).foregroundColor(.fsSecondaryLabel)
                            Toggle("", isOn: Binding(get: { r.enabled }, set: { v in
                                var copy = r; copy.enabled = v
                                FileRepository.shared.updateKeywordReplaceRule(copy)
                                reload()
                            })).labelsHidden()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                FileRepository.shared.deleteKeywordReplaceRule(r.id)
                                reload()
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                    Button { editing = nil; showEditor = true } label: { Label("新增替换规则", systemImage: "plus") }
                    Button { resetBatch(); showBatch = true } label: { Label("批量新增", systemImage: "text.badge.plus") }
                }

                Section("效果测试") {
                    TextField(scope == KeywordReplace.SCOPE_SCAN ? "输入一个文件名试试" : "输入一段字段内容试试", text: $testText)
                        .autocorrectionDisabled()
                    if !testText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("替换后：").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                            Text(testOutput.isEmpty ? "（结果为空）" : testOutput)
                                .fsFont(.caption).foregroundColor(.fsPrimary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { showRestoreConfirm = true } label: {
                        Label("恢复默认规则", systemImage: "arrow.counterclockwise")
                    }
                    Text("会清空当前「扫描阶段」的全部规则，并重新写入内置默认规则。")
                        .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                }
            }
        }
        .navigationTitle("关键词替换")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = nil; showEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showEditor) {
            KeywordRuleEditorSheet(original: editing, scope: scope,
                                   nextOrder: (rules.map { $0.sortOrder }.max() ?? 0) + 1) { reload() }
        }
        .sheet(isPresented: $showBatch) {
            KeywordBatchSheet(scope: scope, mode: $batchMode, text: $batchText,
                               enabled: $batchEnabled, onSave: { saveBatch() })
        }
        .alert("恢复默认规则", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) { restoreDefaults() }
        } message: {
            Text("将删除「扫描阶段」现有全部规则并写回内置默认规则，此操作不可撤销。")
        }
        .alert(batchEnableTarget == true ? "批量启用" : "批量不启用",
               isPresented: Binding(get: { batchEnableTarget != nil },
                                    set: { if !$0 { batchEnableTarget = nil } })) {
            Button("取消", role: .cancel) { batchEnableTarget = nil }
            Button("确定") {
                if let target = batchEnableTarget { applyBatchEnabled(target) }
                batchEnableTarget = nil
            }
        } message: {
            let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            let action = batchEnableTarget == true ? "启用" : "不启用"
            Text(searching
                 ? "确定将搜索结果中的 \(filtered.count) 条规则设为「\(action)」？"
                 : "确定将当前 \(filtered.count) 条规则设为「\(action)」？")
        }
    }

    /// 批量启用 / 不启用：仅对当前列表（搜索命中）的规则生效，写库后返回上一页再进入依旧保留。
    private func applyBatchEnabled(_ enabled: Bool) {
        let ids = filtered.map { $0.id }
        guard !ids.isEmpty else { return }
        FileRepository.shared.setKeywordRulesEnabled(ids: ids, enabled: enabled)
        FileRepository.shared.logOperation(
            level: "INFO", tag: "关键词替换",
            message: "批量\(enabled ? "启用" : "不启用") \(ids.count) 条 scope=\(scope)")
        reload()
    }

    private func move(_ r: KeywordReplaceRule, up: Bool) {
        let list = scoped
        guard let idx = list.firstIndex(where: { $0.id == r.id }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < list.count else { return }
        var a = list[idx], b = list[target]
        swap(&a.sortOrder, &b.sortOrder)
        FileRepository.shared.updateKeywordReplaceRule(a)
        FileRepository.shared.updateKeywordReplaceRule(b)
        reload()
    }

    private func restoreDefaults() {
        for r in rules where r.scope == KeywordReplace.SCOPE_SCAN {
            FileRepository.shared.deleteKeywordReplaceRule(r.id)
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for d in KeywordReplace.DEFAULT_KEYWORD_RULES {
            var r = KeywordReplaceRule()
            r.scope = KeywordReplace.SCOPE_SCAN
            r.pattern = d.pattern
            r.replacement = d.replacement
            r.sortOrder = d.sortOrder
            r.enabled = true
            r.createdAt = now
            _ = FileRepository.shared.saveKeywordReplaceRule(r)
        }
        scope = KeywordReplace.SCOPE_SCAN
        reload()
    }

    private func reload() { rules = FileRepository.shared.getKeywordReplaceRules() }

    private func resetBatch() {
        batchMode = "remove"
        batchText = ""
        batchEnabled = true
    }

    private func saveBatch() {
        let lines = batchText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        if batchMode == "replace" {
            let bad = lines.first(where: { line in
                guard let idx = line.range(of: "||") else { return true }
                return line[line.startIndex..<idx.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty
            })
            if bad != nil { return }
        }
        var order = (rules.map { $0.sortOrder }.max() ?? 0)
        for line in lines {
            order += 1
            var rule = KeywordReplaceRule()
            rule.scope = scope
            rule.enabled = batchEnabled
            rule.sortOrder = order
            if batchMode == "replace" {
                if let idx = line.range(of: "||") {
                    rule.pattern = String(line[line.startIndex..<idx.lowerBound]).trimmingCharacters(in: .whitespaces)
                    rule.replacement = String(line[idx.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            } else {
                rule.pattern = String(line)
                rule.replacement = ""
            }
            FileRepository.shared.saveKeywordReplaceRule(rule)
        }
        showBatch = false
        reload()
    }
}

/// 关键词规则编辑器（新增/编辑通用）。
struct KeywordRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let original: KeywordReplaceRule?
    let scope: String
    let nextOrder: Int
    let onSaved: () -> Void

    @State private var editScope = KeywordReplace.SCOPE_SCAN
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var enabled = true

    var body: some View {
        NavigationStack {
            Form {
                Picker("作用域", selection: $editScope) {
                    Text("扫描阶段（文件名）").tag(KeywordReplace.SCOPE_SCAN)
                    Text("解析阶段（书名/作者/进度/来源）").tag(KeywordReplace.SCOPE_PARSE)
                }
                Section("匹配") {
                    TextField("原字符串（精确匹配）", text: $pattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("替换") {
                    TextField("替换为（留空 = 删除）", text: $replacement)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section { Toggle("启用", isOn: $enabled) }
            }
            .navigationTitle(original == nil ? "新增替换规则" : "编辑替换规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let o = original {
                    editScope = o.scope; pattern = o.pattern
                    replacement = o.replacement; enabled = o.enabled
                } else {
                    editScope = scope
                }
            }
        }
    }

    private func save() {
        if var r = original {
            r.scope = editScope; r.pattern = pattern
            r.replacement = replacement; r.enabled = enabled
            FileRepository.shared.updateKeywordReplaceRule(r)
        } else {
            var r = KeywordReplaceRule()
            r.scope = editScope; r.pattern = pattern
            r.replacement = replacement; r.enabled = enabled
            r.sortOrder = nextOrder
            r.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
            _ = FileRepository.shared.saveKeywordReplaceRule(r)
        }
        onSaved()
        dismiss()
    }
}

/// 关键词替换规则批量新增（去掉关键词 / 替换关键词）。
struct KeywordBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let scope: String
    @Binding var mode: String        // remove | replace
    @Binding var text: String
    @Binding var enabled: Bool
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("模式") {
                    Picker("模式", selection: $mode) {
                        Text("去掉关键词").tag("remove")
                        Text("替换关键词").tag("replace")
                    }
                    .pickerStyle(.segmented)
                    Toggle("启用", isOn: $enabled)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(mode == "remove"
                         ? "每行一个关键词，作为「删除替换」处理（整行内容将被移除）。"
                         : "每行一条，用 || 分隔「被替换词」和「替换成词」，如 AAA||B 表示 AAA 替换成 B。")
                }
            }
            .navigationTitle("批量新增替换规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave()
                        dismiss()
                    }
                    .disabled(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.isEmpty)
                }
            }
        }
    }
}

// MARK: - 操作日志
struct LogViewerView: View {
    @State private var logs: [LogEntry] = []
    @State private var search = ""

    var body: some View {
        VStack {
            List {
                ForEach(filtered) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(e.level).fsFont(.caption2).foregroundColor(e.level == "E" ? .red : .fsSecondaryLabel)
                            Text(formatLogTime(e.time)).fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                            Text(e.tag).fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                        }
                        Text(e.message).fsFont(.caption)
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("操作日志")
        .searchable(text: $search, prompt: "搜索日志")
        .onAppear { reload() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // 复制全部（对齐安卓 LogViewerScreen 的复制能力）
                    Button("复制全部") {
                        UIPasteboard.general.string = filtered
                            .map { "\(formatLogTime($0.time)) \($0.level)/\($0.tag): \($0.message)" }
                            .joined(separator: "\n")
                    }
                    Button("刷新") { reload() }
                    Divider()
                    Button("清空", role: .destructive) {
                        FileRepository.shared.clearOperationLogs()
                        reload()
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private var filtered: [LogEntry] {
        guard !search.isEmpty else { return logs }
        return logs.filter { $0.message.contains(search) || $0.tag.contains(search) }
    }
    private func reload() { logs = FileRepository.shared.getOperationLogs(limit: 1000).reversed() }
    private func formatLogTime(_ ts: Int64) -> String {
        guard ts > 0 else { return "" }
        let df = DateFormatter(); df.dateFormat = "MM-dd HH:mm:ss"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts) / 1000))
    }
}
