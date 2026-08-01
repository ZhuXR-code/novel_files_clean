import Foundation
import SwiftUI

/// 扫描服务（对齐 Android `ScanService`）：枚举用户选定的文件夹 → 解析书名/作者/进度/来源 → 落库。
/// iOS 通过「文档选择器」选取文件夹，使用安全作用域书签持久化访问权限。
final class ScanService {
    static let shared = ScanService()

    /// 由安全作用域书签解析文件夹 URL。
    private func resolveBookmark(_ base64: String) -> URL? {
        resolveBookmarkURL(base64)
    }

    /// 执行一次扫描。config.folderUri 为书签 base64。返回新建文库 runId。
    /// 注意：@Published 状态统一切回主线程更新，避免后台线程发布导致 UI 异常。
    @discardableResult
    func scan(config: ScanConfig) async -> Int64 {
        let sm = ScanStateManager.shared
        guard let folderURL = resolveBookmark(config.folderUri) else {
            await MainActor.run { sm.status = "error"; sm.errorMsg = "无法解析文件夹权限，请重新选择"; sm.finished = true }
            return -1
        }
        guard folderURL.startAccessingSecurityScopedResource() else {
            await MainActor.run { sm.status = "error"; sm.errorMsg = "无文件夹访问权限"; sm.finished = true }
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

        let processBatch = { (batch: [(url: URL, name: String, size: Int64, date: Int64)]) in
            for item in batch {
                if sm.shouldStop() { return }
                let entity = self.parseItem(url: item.url, name: item.name, size: item.size, date: item.date,
                                            runId: runId, scanRules: useScan ? scanRules : [], parseRules: useParse ? parseRules : [],
                                            deep: deep, exactHash: config.exactHash, now: now)
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
        await MainActor.run { sm.totalFiles = total }
        LogUtil.i("ScanService", "收集到 \(total) 个文件 run=\(runId)")

        if total == 0 {
            FileRepository.shared.setRunFileCount(runId: runId, count: 0)
            await MainActor.run { sm.isScanning = false; sm.finished = true; sm.status = "empty" }
            return runId
        }

        FileRepository.shared.setRunFileCount(runId: runId, count: scanned)
        let done = scanned
        await MainActor.run {
            sm.scannedFiles = done
            sm.progress = total > 0 ? done * 100 / total : 100
            sm.isScanning = false
            sm.finished = true
            sm.status = sm.shouldStop() ? "stopped" : "completed"
        }
        LogUtil.i("ScanService", "扫描完成: \(scanned) 文件 run=\(runId)")
        return runId
    }

    // MARK: - 枚举
    /// 流式枚举：边遍历边把文件按 batchSize 聚合成批，通过 onBatch 回调就地处理（解析+落库），
    /// 随后该批内存即被释放，避免一次性把 20w+ 文件 URL/元信息全量驻留内存。
    /// 返回累计收集到的匹配文件总数（供进度分母使用）。
    private func collect(in dir: URL, recursive: Bool, types: Set<String>, minSize: Int64, excluded: Set<String>, batchSize: Int, onBatch: ([(url: URL, name: String, size: Int64, date: Int64)]) -> Void) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return 0 }
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
                onBatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty { onBatch(batch) }
        return count
    }

    // MARK: - 单文件解析
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
            // 取文件前 64KB 计算（与 PC 端一致）。仅取头部即可区分绝大多数不同文件，
            // 若取太小（如 8KB）会因尾部差异未纳入而产生「误判为重复、误删不同文件」的风险。
            if let sample = readSample(url, maxBytes: 64 * 1024) {
                if deep { encoding = EncodingUtil.detectEncodingName(sample: sample) }
                if exactHash { contentHash = computeContentHash(sample: sample) }
            }
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
        return try? fh.readData(ofLength: maxBytes)
    }

    /// 简单内容指纹（FNV-1a，仅用于精确内容去重开关）：取文件前 64KB 计算。
    private func computeContentHash(sample: Data) -> String {
        var hash: UInt64 = 1469598103934665603
        for b in sample {
            hash ^= UInt64(b)
            hash = hash &* 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
