import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { common } from '@kit.AbilityKit';
import { ScannedFile } from '../model/ScannedFile';
import { ChineseConverter } from '../utils/ChineseConverter';
import { ScanConfig } from '../model/ScanConfig';
import { ScanRun } from '../model/ScanRun';
import { KeywordReplaceRule } from '../model/KeywordReplaceRule';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { KeywordReplaceDao } from '../database/KeywordReplaceDao';
import { Parser } from '../utils/Parser';
import { KeywordReplace } from '../utils/KeywordReplace';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';

export interface ScanProgress {
  processed: number;
  found: number;
  currentFile: string;
}

/**
 * 扫描服务：用 DocumentViewPicker 选择用户目录（已授权），递归遍历 txt 等文件，
 * 解析文件名得到 书名/作者/进度/来源，并应用关键词替换规则，增量写入数据库。
 *
 * 对齐安卓端 FileUtil 优化：
 *  1) 支持外部调用 stop() 立即停止扫描，已收集结果会保留；
 *  2) 进度回调节流，避免 10w 级文件压垮 UI；
 *  3) 保持增量批量写入，即使扫描被中止也不丢已解析结果；
 *  4) 采用 BFS 层级遍历，对同层目录顺序枚举，避免深目录爆栈。
 *
 * 关于 Android SAF "批量 children 查询 + 线程池并行" 的对齐说明：
 * 鸿蒙端 fileIo.listFile(dir) 一次 IPC 即返回整个目录的子项列表，天然等效于
 * DocumentsContract.buildChildDocumentsUriUsingTree 的批量 children 查询，无需像
 * Android SAF 那样逐文件 IPC。HarmonyOS NEXT 的文件 API 当前以同步调用为主，
 * 若后续真机测试出现 10w+ 文件扫描过慢，可再引入 @concurrent + taskpool/worker
 * 将目录枚举放到工作线程；目前单线程 BFS 配合增量写入与回调节流已能满足常规需求。
 *
 * 注意：HarmonyOS 的文件访问 API 在真机/模拟器上请以开发者文档为准；
 * 此处采用 Picker 授权 URI + fileIo 遍历的通用写法，并在遍历时对目录/文件用 URI 拼接子项。
 */
export class ScanService {
  private static readonly BATCH_SIZE: number = 200;
  private static readonly PROGRESS_INTERVAL: number = 16;
  private static stopped: boolean = false;

  /** 请求停止当前正在进行的扫描。runScan 会在下一个检查点退出。 */
  public static stop(): void {
    ScanService.stopped = true;
    LogUtil.i('ScanService', '收到停止扫描请求');
  }

  /** 选择目录，返回用户选中的目录 URI（已获临时访问授权）。 */
  public static async selectDirectory(context: common.Context): Promise<string> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    const uris: string[] = await documentPicker.select(options);
    if (uris.length === 0) {
      throw new Error('未选择任何目录');
    }
    return uris[0];
  }

  /** 执行一次扫描，返回新建的文库 id 与扫到的文件数。 */
  public static async runScan(
    config: ScanConfig,
    onProgress: (p: ScanProgress) => void
  ): Promise<{ runId: number; total: number; stopped: boolean }> {
    ScanService.stopped = false;
    const run: ScanRun = new ScanRun();
    run.name = config.name;
    run.folderUri = config.folderUri;
    run.folderName = config.folderName;
    run.fileTypes = config.fileTypes;
    run.createdAt = Date.now();
    run.fileCount = 0;
    const runId: number = await ScanRunDao.insert(run);

    // 关键词替换规则（已启用、按 scope）
    const scanRules: KeywordReplaceRule[] = await KeywordReplaceDao.getEnabledByScope(KeywordReplace.SCOPE_SCAN);
    const parseRules: KeywordReplaceRule[] = await KeywordReplaceDao.getEnabledByScope(KeywordReplace.SCOPE_PARSE);

    const batch: ScannedFile[] = [];
    let processed: number = 0;
    let found: number = 0;
    let lastReportProcessed: number = 0;
    let currentLevel: string[] = [config.folderUri];

    const flushBatch = async (): Promise<void> => {
      if (batch.length > 0) {
        await ScannedFileDao.insertBatch(batch);
        batch.length = 0;
      }
    };

    const reportProgress = (currentFile: string, force: boolean = false): void => {
      if (force || processed - lastReportProcessed >= ScanService.PROGRESS_INTERVAL) {
        onProgress({ processed: processed, found: found, currentFile: currentFile });
        lastReportProcessed = processed;
      }
    };

    while (currentLevel.length > 0 && !ScanService.stopped) {
      const nextLevel: string[] = [];
      for (const dir of currentLevel) {
        if (ScanService.stopped) {
          break;
        }
        let names: string[] = [];
        try {
          names = await fileIo.listFile(dir);
        } catch (e) {
          LogUtil.e('ScanService', `遍历目录失败: ${dir} -> ${(e as Error).message}`);
          continue;
        }
        for (const name of names) {
          if (ScanService.stopped) {
            break;
          }
          const childUri: string = dir.endsWith('/') ? `${dir}${name}` : `${dir}/${name}`;
          let stat: fileIo.Stat | null = null;
          try {
            stat = await fileIo.stat(childUri);
          } catch (e) {
            continue;
          }
          if (stat.isDirectory()) {
            if (config.recursive && !ScanService.isExcluded(name, config.excludedFolders)) {
              nextLevel.push(childUri);
            }
          } else {
            processed++;
            const ext: string = FormatUtil.getExtension(name);
            if (!ScanService.matchExt(ext, config.fileTypes)) {
              continue;
            }
            if (stat.size / 1024 < config.minSizeKb) {
              continue;
            }
            let fileName: string = name;
            if (scanRules.length > 0) {
              fileName = KeywordReplace.applyRules(fileName, scanRules) ?? fileName;
            }
            const parsed = Parser.parseFileName(fileName);
            if (parseRules.length > 0) {
              parsed.title = KeywordReplace.applyRules(parsed.title, parseRules) ?? parsed.title;
              parsed.author = KeywordReplace.applyRules(parsed.author, parseRules) ?? parsed.author;
              parsed.progress = KeywordReplace.applyRules(parsed.progress, parseRules) ?? parsed.progress;
              parsed.source = KeywordReplace.applyRules(parsed.source, parseRules) ?? parsed.source;
            }
            const rec: ScannedFile = new ScannedFile();
            rec.path = childUri;
            rec.fileName = fileName;
            rec.fileSize = stat.size;
            rec.title = parsed.title;
            rec.author = parsed.author;
            rec.progress = parsed.progress;
            rec.source = parsed.source;
            rec.titlePinyin = ChineseConverter.toPinyin(parsed.title);
            rec.authorPinyin = ChineseConverter.toPinyin(parsed.author);
            rec.contentHash = config.exactHash ? await ScanService.computeMd5(childUri) : '';
            rec.ext = ext;
            rec.scanRunId = runId;
            rec.createdAt = Date.now();
            batch.push(rec);
            found++;
            if (batch.length >= ScanService.BATCH_SIZE) {
              await flushBatch();
            }
            reportProgress(name);
          }
        }
      }
      currentLevel = nextLevel;
    }

    await flushBatch();
    await ScanRunDao.updateFileCount(runId, found);
    const status: string = ScanService.stopped ? '已停止' : '完成';
    LogUtil.operation('扫描', `文库=${config.name} 目录=${config.folderName} 命中=${found} 状态=${status} 文库ID=${runId}`);
    return { runId: runId, total: found, stopped: ScanService.stopped };
  }

  private static isExcluded(name: string, excluded: string): boolean {
    if (!excluded || excluded.trim().length === 0) {
      return false;
    }
    const list: string[] = excluded
      .split(/[;；,，]/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    return list.includes(name);
  }

  private static matchExt(ext: string, fileTypes: string): boolean {
    if (!fileTypes || fileTypes.trim().length === 0) {
      return ext === 'txt' || ext === '';
    }
    const list: string[] = fileTypes
      .split(/[;；,，\s]+/)
      .map((s) => s.trim().toLowerCase())
      .filter((s) => s.length > 0);
    if (list.length === 0) {
      return true;
    }
    return list.includes(ext);
  }

  /** 计算文件内容 MD5（仅当开启精确哈希时调用）。 */
  private static async computeMd5(uri: string): Promise<string> {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const md = cryptoFramework.createMd('MD5');
      const CHUNK: number = 1024 * 1024;
      let off: number = 0;
      while (true) {
        const buf: ArrayBuffer = new ArrayBuffer(CHUNK);
        const len: number = fileIo.readSync(file.fd, buf, { offset: off, length: CHUNK });
        if (len <= 0) {
          break;
        }
        md.updateSync({ data: new Uint8Array(buf.slice(0, len)) });
        off += len;
        if (len < CHUNK) {
          break;
        }
      }
      const digest = md.digestSync();
      const bytes: Uint8Array = new Uint8Array(digest.data);
      let hex: string = '';
      for (let i = 0; i < bytes.length; i++) {
        hex += bytes[i].toString(16).padStart(2, '0');
      }
      return hex;
    } finally {
      fileIo.closeSync(file);
    }
  }
}
