import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { uri } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { ScanRunDao } from '../database/ScanRunDao';
import { LogUtil } from '../utils/LogUtil';
import { FilePermissionUtil } from '../utils/FilePermissionUtil';
import { AppContext } from '../utils/AppContext';

export interface DeleteOptions {
  /** true=删除数据库记录 + 物理源文件（旧默认）；false=仅删除数据库记录，保留源文件。 */
  deleteSource?: boolean;
  /** 进度回调：done 已处理数, total 总数, success 成功数, failed 失败数, current 当前文件名。 */
  onProgress?: (done: number, total: number, success: number, failed: number, current: string) => void;
  /** 单文件完成回调，便于 UI 追加实时日志（成功/失败 + 文件名 + 路径）。 */
  onFileDone?: (info: { id: number; name: string; path: string; ok: boolean; error?: string }) => void;
}

/**
 * 删除服务：支持"删除记录+源文件"或"仅删除记录"。
 * 对齐安卓端 DeleteService 优化：
 *  1) deleteSource 开关；
 *  2) 分批加载实体并删除，避免一次性把上万行读进内存；
 *  3) 删除完成后重算所有受影响文库的 file_count。
 */
export class DeleteService {
  /**
   * 批量删除期间的「重新授权缓存」：key=父目录 URI，value=重新授权返回的新 URI。
   * 同一批删除中，相同父目录下的多个文件只需弹一次 Picker，避免每个文件都让用户重新授权。
   */
  private static reauthCache: Map<string, string> = new Map<string, string>();

  /**
   * 删除单个物理文件，带权限恢复重试。
   *
   * 鸿蒙删除用户文件的根因与正确姿势（官方文档明确）：
   *   a) Picker 授权返回的是「文档树 URI」（file://docs/storage/Users/...），授权记录
   *      绑定该 URI 体系；若落库路径被拼成 file:///storage/...（本机 URI，三个斜杠），
   *      读操作可走挂载路径，但删除/写操作会被判定「应用沙箱外未授权」而失败；
   *   b) 官方明确「文档类 URI（file://docs/...）可直接用于 fs 接口」，且拼接 URI
   *      默认未授权——因此删除必须用文档类 URI 或从其提取的虚拟路径；
   *   c) 应用/设备重启后临时授权失效，需重新授权。
   *
   * 本方法以「文档类 URI」为基准，多形态多候选 + 多阶段重试：
   *   1) 多形态直接删除（文档类 URI → 提取的虚拟 path → 原始串）；
   *   2) 激活父目录持久化权限后重试；
   *   3) 用「重新授权缓存」中已换新的父目录 URI 重建文件 URI 再删（避免同批重复弹 Picker）；
   *   4) 对父目录重新授权（弹一次 Picker），用新目录 URI 重建文件 URI 再删。
   * 全程记录最后一次 BusinessError 的真实 code/message，供 UI 定位（不再用固定文案掩盖）。
   *
   * @returns { ok, error } ok=删除成功（含重试成功）；error=失败原因（真实错误码）
   */
  private static async deleteFileWithRetry(
    f: { id: number; fileName: string; path: string; scanRunId: number }
  ): Promise<{ ok: boolean; error: string }> {
    if (!f.path || f.path.length === 0) {
      return { ok: false, error: 'empty path' };
    }

    // 基准统一为文档类 URI（存量数据可能是 file:///storage/...，一并归一化）
    const fileUri: string = DeleteService.toDocUri(f.path);
    const filePath: string = DeleteService.toRealPath(fileUri);
    let parentUri: string | null = DeleteService.deriveParentUri(fileUri);
    if (parentUri) {
      parentUri = DeleteService.toDocUri(parentUri);
    }
    const fileName: string = DeleteService.basename(fileUri);

    // 1) 多形态直接删除
    let r: { ok: boolean; error: string; code: number } = await DeleteService.tryUnlink(fileUri, f.fileName, '直接删除');
    if (r.ok) {
      return { ok: true, error: '' };
    }

    // 1.5) 文件名漂移恢复：扫描后文件可能被外部改名（插入【草莓】/【精校】等装饰标记），
    // 导致 DB 旧路径 unlink 报「文件不存在」。此时在父目录内查找去装饰后一致的真实文件，
    // 用与 listFile 同款的「裸真实路径」直接 unlink（绕开文档类 URI 编码混合问题）。
    // 这一步应在「重授权」之前，避免误弹 Picker。
    if (parentUri && parentUri.length > 0) {
      const drifted: { fileName: string; realPath: string } | null =
        await DeleteService.findDriftedFile(parentUri, f.fileName);
      if (drifted && drifted.realPath.length > 0) {
        // 优先用裸真实路径删除（listFile 已验证该形态可访问）；失败再退回 URI 形态兼容。
        try {
          await fileIo.unlink(drifted.realPath);
          LogUtil.i('DeleteService', `文件 ${f.fileName} 文件名漂移恢复删除成功(裸路径): ${drifted.realPath}`);
          return { ok: true, error: '' };
        } catch (e) {
          const biz = e as BusinessError;
          LogUtil.w('DeleteService', `文件 ${f.fileName} 文件名漂移恢复(裸路径)失败: code=${biz?.code} ${biz?.message}`);
        }
        // 退回 URI 形态再试（覆盖个别设备对裸路径拒绝的场景）
        const driftedUri: string = DeleteService.rebuildFileUri(parentUri, drifted.fileName);
        r = await DeleteService.tryUnlink(driftedUri, f.fileName, '文件名漂移恢复');
        if (r.ok) {
          return { ok: true, error: '' };
        }
      }
    }

    // 2) 激活父目录持久化权限后重试
    if (parentUri && parentUri.length > 0) {
      if (await FilePermissionUtil.activateUri(parentUri)) {
        r = await DeleteService.tryUnlink(fileUri, f.fileName, '激活权限后');
        if (r.ok) {
          return { ok: true, error: '' };
        }
      }
    }

    // 3) 使用重新授权缓存中的新父目录 URI 重建文件 URI
    if (parentUri && parentUri.length > 0) {
      const cachedNewUri: string | undefined = DeleteService.reauthCache.get(parentUri);
      if (cachedNewUri && cachedNewUri.length > 0) {
        const rebuilt: string = DeleteService.rebuildFileUri(cachedNewUri, fileName);
        r = await DeleteService.tryUnlink(rebuilt, f.fileName, '重建路径(缓存授权)');
        if (r.ok) {
          return { ok: true, error: '' };
        }
      }
    }

    // 4) 对父目录重新授权（同一目录只弹一次 Picker），并用新 URI 重建文件 URI
    // 修复：仅当失败原因是「权限类」错误时才弹 Picker 重授权；13900002=文件不存在
    // （路径形态问题或文件确实缺失）时重授权毫无意义，反而会莫名拉起系统
    // 文件选择器打断删除流程（缺陷：删除过程弹 picker）。
    const ENOENT: number = 13900002;
    if (parentUri && parentUri.length > 0 && r.code !== ENOENT) {
      const ctx: common.Context | null = AppContext.get();
      if (ctx) {
        try {
          let newUri: string = DeleteService.reauthCache.get(parentUri) ?? '';
          if (newUri.length === 0) {
            newUri = await FilePermissionUtil.reauthorizeUri(ctx, parentUri, true);
            if (newUri.length > 0) {
              DeleteService.reauthCache.set(parentUri, newUri);
            }
          }
          if (newUri.length > 0) {
            const rebuilt: string = DeleteService.rebuildFileUri(newUri, fileName);
            r = await DeleteService.tryUnlink(rebuilt, f.fileName, '重新授权后');
            if (r.ok) {
              return { ok: true, error: '' };
            }
          }
        } catch (e2) {
          LogUtil.w('DeleteService', `重新授权后重试仍失败: ${f.fileName} -> ${(e2 as Error).message}`);
        }
      }
    } else if (parentUri && parentUri.length > 0 && r.code === ENOENT) {
      LogUtil.w('DeleteService', `文件 ${f.fileName} 失败原因为文件不存在(13900002)，跳过 Picker 重授权`);
    }

    LogUtil.w('DeleteService', `文件 ${f.fileName}（${f.path}）删除彻底失败: ${r.error}`);
    return { ok: false, error: r.error };
  }

  /**
   * 执行一次 unlink 尝试：对目标依次用「文档类 URI → 提取的虚拟 path → 原始串」多种
   * 合法形态调用 fileIo.unlink，任一成功即返回成功；全部失败返回最后错误信息。
   * 之所以要多种形态：文档树授权下 fileIo 对 URI 与 path 的支持在部分系统版本不一致，
   * 全部尝试可覆盖「stat 可读但 unlink 对某一种形态拒绝授权」的场景。
   */
  private static async tryUnlink(target: string, name: string, stage: string): Promise<{ ok: boolean; error: string; code: number }> {
    if (!target || target.length === 0) {
      return { ok: false, error: 'empty target', code: -1 };
    }
    const candidates: string[] = DeleteService.buildUnlinkCandidates(target);
    let lastErr: string = '';
    let lastCode: number = -1;
    for (const c of candidates) {
      try {
        await fileIo.unlink(c);
        LogUtil.i('DeleteService', `文件 ${name} ${stage}删除成功: ${c}`);
        return { ok: true, error: '', code: 0 };
      } catch (e) {
        const biz = e as BusinessError;
        const code: number = biz && typeof biz.code === 'number' ? biz.code : -1;
        lastCode = code;
        lastErr = `code=${code} ${biz && biz.message ? biz.message : String(e)}`;
        LogUtil.w('DeleteService', `文件 ${name} ${stage}删除失败[候选 ${c}]: ${lastErr}`);
      }
    }
    return { ok: false, error: lastErr, code: lastCode };
  }

  /**
   * 生成 unlink 尝试的候选集合（去重），覆盖文档树授权下 fileIo 支持的多种合法形态：
   *   1) 文档类 URI（file://docs/storage/...）—— 授权体系认可，文档类 URI 可直接用于 fs 接口；
   *   2) 提取 path 后的虚拟路径（/storage/Users/...）—— listFile/stat 可用的形态；
   *   3) 原始传入值。
   */
  private static buildUnlinkCandidates(target: string): string[] {
    const list: string[] = [];
    if (!target || target.length === 0) {
      return list;
    }
    // 优先「裸真实路径」：文档树授权下，file://docs/... 的目录部分可能以 URL 编码形态
    // 存在（如 %E3%80%90），而文件名部分保留原始中文，这种「混合 URI」直接 unlink 在部分
    // 系统版本会报 13900002「文件不存在」。用 uri.URI().path 解码出的 /storage/... 裸路径
    // 与 listFile 同款，最稳定，故置顶优先尝试。
    const p1: string = DeleteService.toRealPath(target);
    if (p1 && p1.length > 0 && !list.includes(p1)) {
      list.push(p1);
    }
    const docUri: string = DeleteService.toDocUri(target);
    if (!list.includes(docUri)) {
      list.push(docUri);
    }
    const p2: string = DeleteService.toRealPath(docUri);
    if (p2 && p2.length > 0 && !list.includes(p2)) {
      list.push(p2);
    }
    if (!list.includes(target)) {
      list.push(target);
    }
    return list;
  }

  /**
   * 文件名「装饰标记」匹配：扫描后文件被外部改名（如插入【草莓】、【精校】、
   * （更78）等中间词）时，DB 记录的旧路径 unlink 会报「文件不存在」。
   * 去掉常见的插入型装饰标记（【...】、〖...〗、＜...＞、全角/半角括号、书名号对），
   * 仅比较剩余 body，命中则认为「同一文件被改名」。
   *
   * 之所以只剥「成对括号类」装饰而非任意差异：避免把真正不同的文件（同名不同内容）
   * 误删——仅当去装饰后完全一致才判定为漂移文件，安全且精准。
   */
  private static stripDecorations(name: string): string {
    if (!name || name.length === 0) {
      return name;
    }
    // 去扩展名后处理，避免 .txt 里的点被误剥
    const dotIdx: number = name.lastIndexOf('.');
    let body: string = name;
    let ext: string = '';
    if (dotIdx > 0) {
      body = name.substring(0, dotIdx);
      ext = name.substring(dotIdx);
    }
    // 成对装饰标记：【...】〖...〗〔...〕＜...＞《...》(...) [...]
    let stripped: string = body;
    for (let pass = 0; pass < 3; pass++) {
      const next: string = stripped
        .replace(/【[^】]*】/g, '')
        .replace(/〖[^〗]*〗/g, '')
        .replace(/〔[^〕]*〕/g, '')
        .replace(/＜[^＞]*＞/g, '')
        .replace(/《[^》]*》/g, '')
        .replace(/\([^)]*\)/g, '')
        .replace(/\[[^\]]*\]/g, '')
        .replace(/【[^】]*】/g, '');
      if (next === stripped) {
        break;
      }
      stripped = next;
    }
    // 去除因剥离产生的多余空格/下划线，并压缩连续空白
    stripped = stripped.replace(/[\s_]+/g, '').trim();
    return stripped + ext;
  }

  /**
   * 文件名漂移恢复：父目录内查找与 DB 文件名「去装饰后一致」的真实文件。
   * 返回 { fileName, realPath }：realPath 是与 listFile 同款的「裸虚拟路径」
   * （/storage/Users/.../真实文件名），该形态已被 listFile 验证可访问，直接用于
   * unlink 可绕开文档类 URI 中「目录部分编码 + 文件名部分原始中文」混合导致的
   * 13900002 找不到文件问题；fileName 用于日志/记录。找不到返回空。
   *
   * @param parentUri 父目录文档类 URI
   * @param dbFileName DB 记录的旧文件名
   */
  private static async findDriftedFile(
    parentUri: string,
    dbFileName: string
  ): Promise<{ fileName: string; realPath: string } | null> {
    if (!parentUri || !dbFileName) {
      return null;
    }
    try {
      // 枚举父目录需要目录访问权限；确保激活（权限已持久化时激活即可枚举）
      await FilePermissionUtil.activateUri(parentUri);
      const parentRealPath: string = DeleteService.toRealPath(parentUri);
      const entries: string[] = await fileIo.listFile(parentRealPath);
      const targetBody: string = DeleteService.stripDecorations(dbFileName);
      if (targetBody.length === 0) {
        return null;
      }
      for (const entry of entries) {
        const entryBase: string = DeleteService.basename(entry);
        if (entryBase === dbFileName) {
          continue; // 完全相同的已尝试过，跳过
        }
        if (DeleteService.stripDecorations(entryBase) === targetBody) {
          const sep: string = parentRealPath.endsWith('/') ? '' : '/';
          const realPath: string = `${parentRealPath}${sep}${entryBase}`;
          LogUtil.i('DeleteService', `文件名漂移匹配: ${dbFileName} -> ${entryBase} (${realPath})`);
          return { fileName: entryBase, realPath };
        }
      }
    } catch (e) {
      LogUtil.w('DeleteService', `目录枚举失败(${parentUri}): ${(e as Error).message}`);
    }
    return null;
  }

  /**
   * 将 URI/路径归一化为鸿蒙「文档类 URI」（file://docs/storage/Users/...）。
   * 只有文档类 URI 在授权体系内：file://docs/... 原样返回；file:///storage/...
   * （本机 URI）或 /storage/...（裸虚拟路径）统一转成 file://docs + /storage/...。
   * 其余形态（沙箱路径、content:// 等）原样返回。
   */
  private static toDocUri(fileUri: string): string {
    if (!fileUri || fileUri.length === 0) {
      return fileUri;
    }
    if (fileUri.startsWith('file://docs')) {
      return fileUri;
    }
    let p: string = fileUri;
    if (fileUri.startsWith('file:///')) {
      p = fileUri.substring('file://'.length);
    }
    if (p.startsWith('/storage/')) {
      return 'file://docs' + p;
    }
    return fileUri;
  }

  /**
   * 将 URI 转为 fileIo 可操作的真实 path。
   * 与 ScanService 的 listFile 处理一致：文档树 URI（file://docs/...）必须提取
   * path 才能被 fileIo 识别；content:// / file:// 均按此处理；纯路径原样返回。
   *
   * 修复：不再依赖 new uri.URI().path 提取+解码——扫描落库的路径常为「目录部分
   * percent-encoded + 文件名部分裸中文/空格」的混合 URI，uri.URI 对含裸空格/中文
   * 的串解析会抛错或返回未解码 path，导致「裸真实路径」候选缺失，unlink 只剩混合
   * URI 一种形态而报 13900002。这里手动剥离 scheme 前缀后 decodeURIComponent，
   * 稳定产出 /storage/... 裸路径（该形态已被 listFile/漂移删除验证可访问可删）。
   */
  private static toRealPath(fileUri: string): string {
    if (!fileUri || fileUri.length === 0) {
      return fileUri;
    }
    try {
      let p: string = '';
      if (fileUri.startsWith('file://docs')) {
        p = fileUri.substring('file://docs'.length);
      } else if (fileUri.startsWith('file://')) {
        p = fileUri.substring('file://'.length);
      } else if (fileUri.startsWith('content://')) {
        // content:// 需要真正的 URI 解析，保留原实现并兜底
        const up: string = new uri.URI(fileUri).path;
        return (up && up.length > 0) ? up : fileUri;
      } else {
        // 裸路径：仍需解码可能残留的 percent 编码（存量数据）
        p = fileUri;
      }
      return DeleteService.decodePercent(p);
    } catch (e) {
      // 提取失败则原样返回
      return fileUri;
    }
  }

  /**
   * 解码路径中的 percent 编码（%E3%80%90 → 【 等）。
   * decodeURIComponent 按 UTF-8 多字节正确解码；异常（孤立 % 等非法序列）时
   * 原样返回，避免为解码失败而丢失整个裸路径候选。
   */
  private static decodePercent(p: string): string {
    if (p.indexOf('%') < 0) {
      return p;
    }
    try {
      return decodeURIComponent(p);
    } catch (e) {
      return p;
    }
  }

  /**
   * 用新的父目录 URI 重建文件 URI。
   * 新 URI 可能带或不带末尾 /，统一拼接文件名。
   */
  private static rebuildFileUri(parentUri: string, fileName: string): string {
    if (fileName.length === 0) {
      return parentUri;
    }
    const sep: string = parentUri.endsWith('/') ? '' : '/';
    return `${parentUri}${sep}${fileName}`;
  }

  /** 从 URI/路径提取末尾文件名（最后一段）。 */
  private static basename(fileUri: string): string {
    if (!fileUri || fileUri.length === 0) {
      return '';
    }
    const idx: number = fileUri.lastIndexOf('/');
    if (idx < 0) {
      return fileUri;
    }
    return fileUri.substring(idx + 1);
  }

  /**
   * 从文件 URI 推导其父目录 URI。
   * 支持 content:// / file:// / 纯路径等格式。
   */
  private static deriveParentUri(fileUri: string): string | null {
    if (!fileUri || fileUri.length === 0) {
      return null;
    }
    // 去掉末尾文件名部分，保留到最后的 /
    const idx: number = fileUri.lastIndexOf('/');
    if (idx <= 0) {
      return null;
    }
    return fileUri.substring(0, idx);
  }

  /**
   * 删除指定 id 的文件。
   * @returns { deleted, failed } 成功/失败数。
   */
  public static async deleteByIds(
    ids: number[],
    options: DeleteOptions = {}
  ): Promise<{ deleted: number; failed: number }> {
    if (ids.length === 0) {
      return { deleted: 0, failed: 0 };
    }
    const deleteSource: boolean = options.deleteSource !== false;
    const BATCH: number = 200;
    // 进度回调节流：与扫描侧 ScanService.PROGRESS_INTERVAL=16 对齐。
    // 10w 文件若每删一个就回调一次 onProgress，UI 线程需 10w 次 @State 刷新必然卡顿。
    const PROGRESS_INTERVAL: number = 16;
    let deleted: number = 0;
    let failed: number = 0;
    let done: number = 0;
    let lastReportDone: number = 0;
    const total: number = ids.length;
    const affectedRuns: Set<number> = new Set<number>();

    LogUtil.i('DeleteService', `[操作] 开始删除：共 ${total} 个文件（${deleteSource ? '删除记录+源文件' : '仅删除记录'}）`);

    for (let start: number = 0; start < ids.length; start += BATCH) {
      const batch: number[] = ids.slice(start, Math.min(start + BATCH, ids.length));
      const files = await ScannedFileDao.getByIds(batch);
      // 本批物理删除成功的 id，待本批结束统一入库删除（deleteByIds 内部再按 500 分块），
      // 避免逐条 deleteByIds([f.id]) 造成 10w 文件 = 10w 次 DB 往返。
      const successIds: number[] = [];
      for (const f of files) {
        done++;
        let ok: boolean = false;
        let errMsg: string | undefined = undefined;
        if (deleteSource) {
          const res = await DeleteService.deleteFileWithRetry(f);
          ok = res.ok;
          if (!ok) {
            errMsg = res.error.length > 0 ? res.error : '权限失效或文件不存在';
          }
        } else {
          // 仅删记录，直接视为成功
          ok = true;
        }
        if (ok) {
          successIds.push(f.id);
          deleted++;
          affectedRuns.add(f.scanRunId);
        } else {
          failed++;
          LogUtil.w('DeleteService', `物理删除失败，保留记录: ${f.fileName} (${f.path})`);
        }
        if (options.onFileDone) {
          options.onFileDone({ id: f.id, name: f.fileName, path: f.path, ok: ok, error: ok ? undefined : errMsg });
        }
        // 节流：仅当累计增量 ≥ PROGRESS_INTERVAL 才回调进度，避免每文件一次 UI 刷新。
        if (options.onProgress && done - lastReportDone >= PROGRESS_INTERVAL) {
          options.onProgress(done, total, deleted, failed, f.fileName);
          lastReportDone = done;
        }
      }
      // 批量删除本批成功文件的数据库记录（一次 DELETE 替代逐条删除）。
      if (successIds.length > 0) {
        await ScannedFileDao.deleteByIds(successIds);
      }
    }
    // 强制补报最终进度：小批量（< PROGRESS_INTERVAL）时上述节流可能一次都没触发，
    // UI 若停留在 0/0 将无法显示完成状态。
    if (options.onProgress && total > 0 && done - lastReportDone > 0) {
      options.onProgress(done, total, deleted, failed, '');
      lastReportDone = done;
    }

    // 删除完成后，重算所有受影响文库的文件数（回写 scan_run.file_count）
    if (affectedRuns.size > 0) {
      for (const runId of affectedRuns) {
        const n: number = await ScannedFileDao.countByScanRun(runId);
        await ScanRunDao.updateFileCount(runId, n);
      }
      LogUtil.i('DeleteService', `重算 ${affectedRuns.size} 个文库文件数完成`);
    }

    LogUtil.operation('删除', `共=${total} 成功=${deleted} 失败=${failed} deleteSource=${deleteSource}`);
    return { deleted: deleted, failed: failed };
  }

  /** 删除某文库下全部文件。 */
  public static async deleteAllInRun(
    runId: number,
    options: DeleteOptions = {}
  ): Promise<{ deleted: number; failed: number }> {
    // 仅投影 id 列，避免加载 10w+ 完整对象仅为取 id 的内存浪费。
    const ids: number[] = await ScannedFileDao.getIdsByScanRun(runId);
    return await DeleteService.deleteByIds(ids, options);
  }
}
