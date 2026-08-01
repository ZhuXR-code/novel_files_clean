import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("文包清理助手（iOS 版）使用说明").fsFont(.title2).fontWeight(.bold)
                group("1. 扫描文件", items: [
                    "点击「选择文件夹开始扫描」，在系统文件选择器中挑选一个文件夹（如「文件」App 中的目录、iCloud Drive、或连接电脑同步的目录）。",
                    "iOS 出于隐私限制，App 只能访问你主动选择的文件夹及其子目录；授权后 iOS 会记住该文件夹以便后续读取与删除。",
                    "扫描时按文件名解析「书名 / 作者 / 进度 / 来源」，并在「深度模式」下识别编码。解析逻辑与安卓端、电脑端完全一致。"
                ])
                group("2. 文库与列表", items: [
                    "「列表模式」按页展示文件，可逐条勾选、标星、预览、重命名。",
                    "「合集模式」按「书名 + 作者」自动聚合，方便发现重复作品。",
                    "支持搜索、按多种字段排序、按书名/作者/进度/来源前缀筛选。"
                ])
                group("3. 一键清理", items: [
                    "进入「一键清理」，App 按「勾选重复五则规则」自动标记重复文件（最新/最大/进度最大者保留，含中文进度与完结文件保护）。",
                    "可在「设置 → 勾选重复规则」中开关内置规则，或新增自定义条件-动作规则。",
                    "确认后执行删除，可选择「同时删除磁盘文件」或「仅移除记录」。"
                ])
                group("4. 其他功能", items: [
                    "「关键词替换规则」：在扫描/解析阶段对文件名与字段做精确字符串替换（如去除水印、推广语）。",
                    "「操作日志」：记录每一次删除、标记、规则变更，便于追溯。",
                    "所有数据均保存在本机 SQLite 数据库（沙盒内），不上传任何服务器。"
                ])
                Text("本 App 为「txt 文件清理」工程的 iOS 端实现，功能与安卓端保持对齐。")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
            }
            .padding()
        }
        .navigationTitle("使用帮助")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fsFont(.headline)
            ForEach(items, id: \.self) { t in
                Text("• " + t).fsFont(.subheadline).foregroundColor(.fsSecondaryLabel)
            }
        }
    }
}
