import Foundation
import SwiftUI
import CryptoKit

/// 扫描服务（对齐 Android `ScanService`）：枚举用户选定的文件夹 → 解析书名/作者/进度/来源 → 落库。
/// iOS 通过「文档选择器」选取文件夹，使用安全作用域书签持久化访问权限。
final class ScanService {
    static let shared = ScanService()

    /// 由安全作用域书签解析文件夹 URL。
    private func resolveBookmark(_ base64: String) -> URL? {
        resolveBookmarkURL(base64)?.url
    }

    /// 执行一次扫描。config.folderUri 为书签 base64。返回新建文库 runId。
    /// 注意：@Published 状态统一切回主线程更新，避免后台线程发布导致 UI 异常。
    @discardableResult
    func scan(config: ScanConfig) async -> Int64 {
        LogUtil.i("ScanService", "开始扫描 配置「\(config.name)」 文件夹=\(config.folderName) 类型=\(config.fileTypes) 模式=\(config.scanMode) 递归=\(config.recursive)")
        let sm = ScanStateManager.shared
        guard let folderURL = resolveBookmark(config.folderUri) else {
            await MainActor.run { sm.status = "error"; sm.errorMsg = "无法解析文件夹权限，请重新选择"; sm.finished = true }
            FileRepository.shared.logOperation(level: "W", tag: "扫描", message: "扫描失败：无法解析文件夹权限（配置「\(config.name)」）")
            return -1
        }
        guard folderURL.startAccessingSecurityScopedResource() else {
            await MainActor.run { sm.status = "error"; sm.errorMsg = "无文件夹访问权限"; sm.finished = true }
            FileRepository.shared.logOperation(level: "W", tag: "扫描", message: "扫描失败：无文件夹访问权限（配置「\(config.name)」）")
            return -1
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        await MainActor.run { sm.reset(); sm.isScanning = true; sm.phase = "collecting" }
        let runName = config.name.isEmpty ? (config.folderName.isEmpty ? "文库" : config.folderName) : config.name
        let runId = FileRepository.shared.createScanRun(name: runName, folderUri: config.folderUri, folderName: config.folderName, fileTypes: config.fileTypes)
        await MainActor.run { sm.runId = runId }

        let types = Set(config.fileTypes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
        let minSize = Int64(config.minSizeKb) * 1024
        let excluded = Set(config.excludedFolders.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })

        // 解析“排除原始书名 / 排除书名词汇”：按逗号或换行切分，去空白、去空项。
        // 命中任一项的书名在解析后剔除（等同该文件被跳过，不入库）。
        let excludedTitles = Set((config.excludedTitles ?? "")
            .split(separator: ",", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: "\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        let excludedTitleKeywords = (config.excludedTitleKeywords ?? "")
            .split(separator: ",", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: "\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hasTitleExclude = !excludedTitles.isEmpty || !excludedTitleKeywords.isEmpty

        // 收集 + 解析阶段（流式分批，避免一次性把 20w+ 文件 URL/元信息全量驻留内存导致 OOM）。
        // collect 每收集 BATCH 个文件就回调一次，本函数在回调内就地解析并批量落库，随后释放该批。
        let scanRules = FileRepository.shared.getEnabledRules(scope: KeywordReplace.SCOPE_SCAN)
        let parseRules = FileRepository.shared.getEnabledRules(scope: KeywordReplace.SCOPE_PARSE)
        let useScan = !scanRules.isEmpty
        let useParse = !parseRules.isEmpty
        let deep = config.scanMode == "deep"
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        var total = 0
        var scanned = 0
        var buffer: [ScannedFile] = []
        let batchSize = 5000

        await MainActor.run { sm.phase = "scanning" }

        let processBatch = { (batch: [(url: URL, name: String, size: Int64, date: Int64)], runningTotal: Int) in
            total = runningTotal
            for item in batch {
                if sm.shouldStop() { return }
                let entity = self.parseItem(url: item.url, name: item.name, size: item.size, date: item.date,
                                            runId: runId, scanRules: useScan ? scanRules : [], parseRules: useParse ? parseRules : [],
                                            deep: deep, exactHash: config.exactHash, now: now)
                // 命中“排除原始书名 / 排除书名词汇”的文件：解析后剔除，不入库（等同扫描跳过）
                if hasTitleExclude && Self.titleExcluded(entity.title, exact: excludedTitles, keywords: excludedTitleKeywords) {
                    continue
                }
                buffer.append(entity)
                scanned += 1
                if buffer.count >= 100 {
                    FileRepository.shared.insertAll(buffer); buffer.removeAll()
                }
                if scanned % 64 == 0 {
                    let s = scanned, n = item.name, t = total
                    Task { @MainActor in
                        sm.scannedFiles = s
                        sm.totalFiles = t
                        sm.progress = t > 0 ? s * 100 / t : 0
                        sm.currentFile = n
                    }
                }
            }
        }

        total = collect(in: folderURL, recursive: config.recursive, types: types, minSize: minSize,
                        excluded: excluded, batchSize: batchSize, onBatch: processBatch)
        if !buffer.isEmpty { FileRepository.shared.insertAll(buffer) }
        let totalCount = total
        await MainActor.run { sm.totalFiles = totalCount }
        LogUtil.i("ScanService", "收集到 \(total) 个文件 run=\(runId)")

        if total == 0 {
            LogUtil.w("ScanService", "文库为空，未找到匹配文件 run=\(runId) 类型=\(config.fileTypes)")
            FileRepository.shared.setRunFileCount(runId: runId, count: 0)
            await MainActor.run { sm.isScanning = false; sm.finished = true; sm.status = "empty" }
            return runId
        }

        FileRepository.shared.setRunFileCount(runId: runId, count: scanned)
        let done = scanned
        let totalForProgress = total
        await MainActor.run {
            sm.scannedFiles = done
            sm.progress = totalForProgress > 0 ? done * 100 / totalForProgress : 100
            sm.isScanning = false
            sm.finished = true
            sm.status = sm.shouldStop() ? "stopped" : "completed"
        }
        LogUtil.i("ScanService", "扫描完成: \(scanned) 文件 run=\(runId)")
        let statusMsg = sm.shouldStop() ? "（已停止）" : ""
        FileRepository.shared.logOperation(level: "I", tag: "扫描", message: "扫描完成：文库 \(runId) 共 \(scanned) 个文件\(statusMsg)")
        return runId
    }

    // MARK: - 枚举
    /// 流式枚举：边遍历边把文件按 batchSize 聚合成批，通过 onBatch 回调就地处理（解析+落库），
    /// 随后该批内存即被释放，避免一次性把 20w+ 文件 URL/元信息全量驻留内存。
    /// onBatch 第二个参数是当前已发现的匹配文件总数（用于驱动扫描进度条分母）。
    /// 返回累计收集到的匹配文件总数。
    private func collect(in dir: URL, recursive: Bool, types: Set<String>, minSize: Int64, excluded: Set<String>, batchSize: Int, onBatch: ([(url: URL, name: String, size: Int64, date: Int64)], Int) -> Void) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            LogUtil.e("ScanService", "枚举器创建失败（权限/路径无效） dir=\(dir.path)")
            return 0
        }
        var batch: [(url: URL, name: String, size: Int64, date: Int64)] = []
        batch.reserveCapacity(batchSize)
        var count = 0
        for case let url as URL in enumerator {
            if ScanStateManager.shared.shouldStop() { break }
            // 排除文件夹：URL 路径含被排除的目录名段
            let lastComp = url.lastPathComponent
            if excluded.contains(lastComp) {
                enumerator.skipDescendants()
                continue
            }
            guard let res = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else { continue }
            if res.isDirectory == true {
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard types.contains(ext) else { continue }
            let size = Int64(res.fileSize ?? 0)
            guard size >= minSize else { continue }
            let date = (res.contentModificationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970
            batch.append((url: url, name: url.lastPathComponent, size: size, date: Int64(date * 1000)))
            count += 1
            if batch.count >= batchSize {
                onBatch(batch, count)
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty { onBatch(batch, count) }
        return count
    }

    // MARK: - 单文件解析
    /// 判断某书名是否命中“排除原始书名 / 排除书名词汇”。
    /// - exact：精确书名集合，完全相同才剔除；
    /// - keywords：书名词汇列表，书名包含任一词汇即剔除。
    /// 两者为“或”关系（命中任一即排除）。title 为空时不算命中。
    static func titleExcluded(_ title: String, exact: Set<String>, keywords: [String]) -> Bool {
        if title.isEmpty { return false }
        if exact.contains(title) { return true }
        for kw in keywords {
            if title.contains(kw) { return true }
        }
        return false
    }

    private func parseItem(url: URL, name: String, size: Int64, date: Int64, runId: Int64,
                           scanRules: [KeywordReplaceRule], parseRules: [KeywordReplaceRule],
                           deep: Bool, exactHash: Bool, now: Int64) -> ScannedFile {
        let rawName = name
        let fileName = KeywordReplace.applyRules(rawName, scanRules) ?? rawName
        let parsed = Parser.parseFileName(fileName)
        let title = KeywordReplace.applyRules(parsed.title, parseRules) ?? parsed.title
        let author = KeywordReplace.applyRules(parsed.author, parseRules) ?? parsed.author
        let progress = KeywordReplace.applyRules(parsed.progress, parseRules) ?? parsed.progress
        let source = KeywordReplace.applyRules(parsed.source, parseRules) ?? parsed.source

        var encoding = ""
        var contentHash = ""
        if deep || exactHash {
            // 深度扫描读取文件头用于编码识别；内容哈希若开启则读取完整内容计算 MD5（与安卓端一致：整文件 MD5）。
            if let sample = readSample(url, maxBytes: 64 * 1024) {
                if deep { encoding = EncodingUtil.detectEncodingName(sample: sample) }
            }
            if exactHash { contentHash = computeContentHash(url: url) }
        }

        return ScannedFile(
            path: url.absoluteString,
            fileName: fileName,
            fileSize: size,
            title: title,
            author: author,
            progress: progress,
            source: source,
            encoding: encoding,
            titlePinyin: ChineseConverter.toPinyin(title),
            authorPinyin: ChineseConverter.toPinyin(author),
            contentHash: contentHash,
            ext: url.pathExtension.lowercased(),
            marked: 0,
            checked: 0,
            scanRunId: runId,
            createdAt: now,
            fileDate: date > 0 ? date : nil
        )
    }

    private func readSample(_ url: URL, maxBytes: Int) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: maxBytes)
        guard !data.isEmpty else { return nil }
        // 关键：FileHandle.readData 在 security-scoped 容器内文件上会返回对 NSData 的桥接 Data，
        // 其 `count` 与底层 buffer 实际可访问长度可能不一致。后续对它的下标访问
        // （如 detectEncodingAndBom 的 sample[0..2]）会触发 Data.subscript 的
        // _preconditionFailure（SIGTRAP），表现为深度扫描闪退。
        // 用 withUnsafeBytes 复制成独立 [UInt8] 再包回 Data，彻底脱离 NSData 桥接，避免越界 trap。
        let bytes: [UInt8] = data.withUnsafeBytes { Array($0) }
        return Data(bytes)
    }

    private func readFileData(_ url: URL) -> Data? {
        // 关键：不能用 Data(contentsOf: .alwaysMapped) 直接 mmap。
        // security-scoped 容器文件在扫描并发池线程上用 mmap/filehandle 读取出的 NSData 桥接对象，
        // 其底层 buffer 与 Swift Data 视图长度可能不一致，后续 Insecure.MD5.hash 逐字节访问时
        // 会触发 Data.subscript 的 _preconditionFailure（SIGTRAP），表现为勾选「计算内容指纹」闪退。
        // 改为逐块读取、每块用 withUnsafeBytes 复制成独立 [UInt8]（完全脱离 NSData 桥接），
        // 再拼成标准 owned Data，彻底隔离脏 buffer，避免越界 trap。
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var bytes: [UInt8] = []
        let chunk = 256 * 1024
        while true {
            let piece = fh.readData(ofLength: chunk)
            guard !piece.isEmpty else { break }
            // 复制成独立的 [UInt8]，切断与桥接 NSData 的一切关联
            let part: [UInt8] = piece.withUnsafeBytes { Array($0) }
            bytes.append(contentsOf: part)
        }
        return Data(bytes)
    }

    /// 内容指纹（MD5，整文件）：与安卓端 computeContentHash 一致（整文件内容计算 MD5 十六进制小写）。
    /// 仅当开启「内容哈希」开关（精确内容去重）时调用，文件较大时读取整文件有一定 IO 开销（已在扫描并发池内执行）。
    private func computeContentHash(url: URL) -> String {
        guard let data = readFileData(url) else { return "" }
        // 关键：不用 Insecure.MD5.hash(data:) 一次性提交整段 Data。该 API 内部会对 Data 做连续下标遍历，
        // 若传入的 Data 仍是桥接脏 buffer（count 与底层 length 不一致）就会触发 Data.subscript 越界 trap。
        // 改为流式 update + finalize，且 data 已由 readFileData 复制为独立 owned，双保险隔离脏桥接。
        var hasher = Insecure.MD5()
        data.withUnsafeBytes { buf in
            hasher.update(data: buf)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
