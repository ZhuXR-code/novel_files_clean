import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Preferences

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
                Picker("阅读字号", selection: $prefs.fontScaleMode) {
                    Text("小").tag("small")
                    Text("标准").tag("standard")
                    Text("大").tag("large")
                }
                Picker("预览滚动条", selection: $prefs.previewScrollbarMode) {
                    Text("右侧纵向").tag("vertical")
                    Text("横向").tag("horizontal")
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
            Section {
                Button { router.navigate(.help) } label: { Label("使用帮助", systemImage: "questionmark.circle") }
            }
        }
        .navigationTitle("设置")
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

// MARK: - 勾选重复规则
struct DupRuleView: View {
    @EnvironmentObject var router: Router
    @State private var builtins: [DupRuleConfig] = []
    @State private var userRules: [DupRuleConfig] = []
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newField = "file_name"
    @State private var newRegex = ""
    @State private var newAction = "check"

    var body: some View {
        List {
            Section("内置规则（五则）") {
                ForEach($builtins) { $c in
                    Toggle(isOn: Binding(get: { $c.wrappedValue.enabled }, set: { v in
                        $c.wrappedValue.enabled = v
                        FileRepository.shared.setDupRuleEnabled(key: $c.wrappedValue.ruleKey, enabled: v)
                    })) {
                        VStack(alignment: .leading) {
                            Text($c.wrappedValue.ruleName).font(.subheadline)
                            Text($c.wrappedValue.desc).font(.caption2).foregroundColor(.fsSecondaryLabel)
                        }
                    }
                }
            }
            Section("自定义规则") {
                ForEach($userRules) { $c in
                    HStack {
                        VStack(alignment: .leading) {
                            Text($c.wrappedValue.ruleName.isEmpty ? "(未命名)" : $c.wrappedValue.ruleName).font(.subheadline)
                            Text("动作: \($c.wrappedValue.action == "protect" ? "保护(不勾选)" : "勾选(待删)") · 条件: \($c.wrappedValue.conditions ?? "")")
                                .font(.caption2).foregroundColor(.fsSecondaryLabel)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { $c.wrappedValue.enabled }, set: { v in
                            $c.wrappedValue.enabled = v
                            var copy = $c.wrappedValue; copy.enabled = v
                            FileRepository.shared.saveDupRuleConfig(copy)
                        }))
                        .labelsHidden()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            FileRepository.shared.deleteDupRuleConfig($c.wrappedValue.id)
                            reload()
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
                Button { showAdd = true } label: { Label("新增自定义规则", systemImage: "plus") }
            }
        }
        .navigationTitle("勾选重复规则")
        .onAppear { reload() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section("规则名称") { TextField("如：保护精校版", text: $newName) }
                    Section("满足条件时") {
                        Picker("动作", selection: $newAction) {
                            Text("勾选（待删）").tag("check")
                            Text("保护（不勾选）").tag("protect")
                        }
                    }
                    Section("条件（命中字段的正则）") {
                        Picker("字段", selection: $newField) {
                            Text("文件名").tag("file_name")
                            Text("书名").tag("novel_name")
                            Text("作者").tag("author")
                            Text("进度").tag("progress")
                            Text("来源").tag("source")
                        }
                        TextField("正则表达式，如 水印", text: $newRegex)
                    }
                }
                .navigationTitle("新增规则").toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("取消") { showAdd = false } }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") {
                            let json = "[{\"field\":\"\(newField)\",\"regex\":\"\(newRegex)\"}]"
                            var c = DupRuleConfig()
                            c.ruleName = newName
                            c.conditions = json
                            c.action = newAction
                            c.enabled = true
                            FileRepository.shared.saveDupRuleConfig(c)
                            showAdd = false; newName = ""; newRegex = ""
                            reload()
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        let all = FileRepository.shared.getDupRuleConfigs()
        builtins = all.filter { $0.isBuiltin }
        userRules = all.filter { !$0.isBuiltin }
    }
}

// MARK: - 关键词替换规则
struct KeywordReplaceView: View {
    @State private var rules: [KeywordReplaceRule] = []
    @State private var showAdd = false
    @State private var newScope = KeywordReplace.SCOPE_SCAN
    @State private var newPattern = ""
    @State private var newReplacement = ""

    var body: some View {
        List {
            ForEach($rules) { $r in
                HStack {
                    VStack(alignment: .leading) {
                        Text($r.wrappedValue.pattern).font(.subheadline)
                        Text("作用域: \($r.wrappedValue.scope) · 替换为: \($r.wrappedValue.replacement.isEmpty ? "(删除)" : $r.wrappedValue.replacement)")
                            .font(.caption2).foregroundColor(.fsSecondaryLabel)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { $r.wrappedValue.enabled }, set: { v in
                        $r.wrappedValue.enabled = v
                        FileRepository.shared.updateKeywordReplaceRule($r.wrappedValue)
                    })).labelsHidden()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        FileRepository.shared.deleteKeywordReplaceRule($r.wrappedValue.id)
                        reload()
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
            Button { showAdd = true } label: { Label("新增替换规则", systemImage: "plus") }
        }
        .navigationTitle("关键词替换")
        .onAppear { reload() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Picker("作用域", selection: $newScope) {
                        Text("扫描阶段（文件名）").tag(KeywordReplace.SCOPE_SCAN)
                        Text("解析阶段（书名/作者/进度/来源）").tag(KeywordReplace.SCOPE_PARSE)
                    }
                    Section("匹配") { TextField("原字符串（精确匹配）", text: $newPattern) }
                    Section("替换") { TextField("替换为（留空=删除）", text: $newReplacement) }
                }
                .navigationTitle("新增规则").toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("取消") { showAdd = false } }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") {
                            var r = KeywordReplaceRule()
                            r.scope = newScope; r.pattern = newPattern
                            r.replacement = newReplacement
                            r.sortOrder = (rules.map { $0.sortOrder }.max() ?? 0) + 1
                            r.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
                            FileRepository.shared.saveKeywordReplaceRule(r)
                            showAdd = false; newPattern = ""; newReplacement = ""
                            reload()
                        }.disabled(newPattern.isEmpty)
                    }
                }
            }
        }
    }

    private func reload() { rules = FileRepository.shared.getKeywordReplaceRules() }
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
                            Text(e.level).font(.caption2).foregroundColor(e.level == "E" ? .red : .fsSecondaryLabel)
                            Text(formatLogTime(e.time)).font(.caption2).foregroundColor(.fsSecondaryLabel)
                            Text(e.tag).font(.caption2).foregroundColor(.fsSecondaryLabel)
                        }
                        Text(e.message).font(.caption)
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
                Button("清空") {
                    FileRepository.shared.clearOperationLogs()
                    reload()
                }
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
