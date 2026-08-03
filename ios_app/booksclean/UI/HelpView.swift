import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            MaxWidthContainer {
                VStack(alignment: .leading, spacing: 16) {
                    Text("文包整理清理助手（iOS 版）使用说明").fsFont(.title2).fontWeight(.bold)

                    group("1. 扫描文件", items: [
                        "从首页点击「选择文件夹开始扫描」，在系统文件选择器中挑选一个文件夹。可访问「文件」App 中的「我的 iPhone / iPad」目录、iCloud Drive、或连接电脑同步进来的目录。",
                        "iOS 出于隐私限制，App 只能访问你主动选择的文件夹及其子目录。首次授权后 iOS 会记住该文件夹，后续读取与删除无需再次确认；若你手动撤销了授权，再次操作时会提示重新选择。",
                        "扫描时按文件名解析出「书名 / 作者 / 进度 / 来源」四项。开启首页或配置里的「深度模式」后，会进一步识别文件编码（UTF-8 / GBK 等），解析逻辑与安卓端、电脑端完全一致。",
                        "解析规则说明：文件名常见形如「书名@作者.txt」「[进度]书名.txt」，App 会自动剥离方括号进度、@分隔的作者；无法识别的字段留空，不影响其它字段。"
                    ])

                    group("2. 文库与列表", items: [
                        "「列表模式」按页展示文件，每一行可勾选（√，表示要清理/参与统计）、标星（★，标记为重要/待保留）、预览（头/尾/图片）、重命名。",
                        "「合集模式」按「书名 + 作者」自动聚合同类作品，便于一眼发现重复。点击合集进入可查看该合集下全部文件，合集左上角复选框可「一键勾选 / 取消勾选」整个合集。",
                        "顶部支持：关键词搜索（文件名/书名/作者）、按书名/作者/大小/修改时间等字段排序（升/降序切换）、按书名/作者/进度/来源前缀筛选。",
                        "「每页行数」可在分页栏调整（如 50 / 100 / 200）；支持首页 / 上页 / 下页 / 末页及跳页，便于大文库快速定位。",
                        "「合集设置」（更多菜单中）可调整：最小合集数量（低于则忽略）、最大数量上限、以及用逗号分隔的「排除书名」（这些书名不参与合集聚合）。"
                    ])

                    group("3. 一键清理", items: [
                        "进入「一键清理」，App 按「勾选重复五则规则」自动标记重复文件：在所有同名或同书名的重复项中，保留「最新修改 / 体积最大 / 进度最大」的版本，其余自动勾选删除，并保护「含中文进度的完结文件」避免误删。",
                        "规则细节可改：在「设置 → 勾选重复规则」中开关内置规则，或新增自定义「条件 → 动作」规则（例如：当文件名含某关键词时自动勾选/标星）。",
                        "确认清单后执行删除。两种模式：①「同时删除磁盘文件」——从设备真实移除文件（不可恢复，请先核对）；②「仅移除记录」——只从 App 数据库删除条目，文件仍留在原文件夹。"
                    ])

                    group("4. 关键词替换与备份", items: [
                        "「关键词替换规则」在扫描/解析阶段对文件名与字段做精确字符串替换（如批量去除水印、推广语）。支持「批量新增」：一次粘贴多行，两种模式任选——「去掉关键词」每行一个关键词（整行内容被移除），「替换关键词」每行用 || 分隔（如 AAA||B 表示把 AAA 替换成 B）。",
                        "「导出已标记文件清单」位于「设置 → 数据与备份」，把已标星（★）的文件清单导出为文本文件，便于备份待删列表；当没有任何标记文件时会提示。",
                        "「操作日志」记录每一次删除、标记、规则变更，带时间与内容摘要，便于事后追溯与排查。"
                    ])

                    group("5. 隐私与数据安全", items: [
                        "所有扫描结果、标记、规则均保存在本机 SQLite 数据库（App 沙盒内），不联网、不上传任何服务器。",
                        "App 仅在你主动选择文件夹时才获得该目录的读取 / 删除权限，且由 iOS 系统统一管控，可随时在系统「设置 → 文件」或 App 内重新授权。",
                        "建议在执行「同时删除磁盘文件」前，先用「导出已标记文件清单」备份待删列表；删除操作不可逆。"
                    ])

                    group("6. iPad 适配说明", items: [
                        "本 App 同时支持 iPhone 与 iPad。在 iPad 上：首页统计与说明居中显示，文库列表 / 合集改为多列网格以充分利用大屏；文件详情、预览、设置等页面自动约束宽度并居中。",
                        "iPad 上同样使用系统文件选择器访问「文件」App 目录、iCloud Drive 等，授权逻辑与 iPhone 一致。"
                    ])

                    faq

                    Text("本 App 为「txt 文件清理」工程的 iOS 端实现，功能与安卓端保持对齐。")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }
                .padding()
            }
        }
        .navigationTitle("使用帮助")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 常见问题
    private var faq: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("常见问题").fsFont(.headline)
            faqItem("为什么选了文件夹却读不到里面的书？",
                    "iOS 只授权你「点选的那个确切文件夹」。请确认选择的是包含 txt 的目录本身，而不是它的父目录；若文件在「文件」App 的子文件夹层，需在文件选择器里逐层进入再选中最里层目录。")
            faqItem("为什么之前能删，现在提示要重新授权？",
                    "iOS 可能因系统升级或你在系统设置中撤销了授权而失效。重新进入扫描 / 删除流程，在文件选择器里再次选择同一文件夹即可恢复权限。")
            faqItem("删除文件后能找回吗？",
                    "选「同时删除磁盘文件」是真实从设备移除，不可恢复；如只想先整理清单，请选「仅移除记录」。重要文件建议先「导出已标记清单」备份。")
            faqItem("扫描很慢或卡住？",
                    "文库文件极多时解析需要时间，请耐心等待进度条；可在「设置」中关闭「深度模式」（编码识别）以加快扫描，需要时再单独开启。")
            faqItem("iPad 上界面和 iPhone 不一样？",
                    "这是刻意的大屏优化：列表 / 合集改为多列网格、详情页居中，以提升可读性与利用率，功能与 iPhone 完全一致。")
        }
    }

    private func group(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fsFont(.headline)
            ForEach(items, id: \.self) { t in
                Text("• " + t).fsFont(.subheadline).foregroundColor(.fsSecondaryLabel)
            }
        }
    }

    private func faqItem(_ q: String, _ a: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Q：" + q).fsFont(.subheadline).fontWeight(.medium)
            Text("A：" + a).fsFont(.caption).foregroundColor(.fsSecondaryLabel)
        }
        .padding(.top, 2)
    }
}
