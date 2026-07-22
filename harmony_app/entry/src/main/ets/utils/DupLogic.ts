import { ScannedFileDao } from '../database/ScannedFileDao';
import { DuplicateRow } from '../model/DuplicateRow';
import { LogUtil } from './LogUtil';

/**
 * 复刻并增强 PC 端 /api/groups/select-duplicates 的“标记重复（勾选）”逻辑，
 * 完整对齐安卓端 FileRepository.selectDuplicateIds（五则规则）。
 *
 * 所有判定在【同一文库】内、按 (作者 + 书名) 子分组进行：
 *  规则1 完全相等去重：(文件名 + 大小 + 进度) 三元组完全一致，同组>=2本时最新(createdAt 最晚，并列取 id 最大)不勾选，其余全部勾选。
 *  规则2 纯数字进度对比：同组所有进度均为纯数字时，数字最大者不勾选，其余全部勾选。
 *  规则3 含中文进度/完结特例：含中文进度者不勾选；若同组存在文件名带完结关键词且其“进度数字最大文件”更小，则该数字最大文件强制勾选。
 *  规则4 最大文件不勾选：本组内唯一文件大小最大者不勾选（并列最大则不作保护）。
 *  规则5 完结+N番外：进度严格匹配「完结+数字番外」者按 N 排序，N 最大不勾选，其余强制勾选（覆盖规则3A），但恰为本组文件大小最大者也不勾选。
 *
 * 返回应勾选的 id 列表，并直接把结果持久化写入 checked=1（标记重复即“勾选”）。
 * 仅新增勾选、不清空其它已勾选，保证“合并勾选”语义。
 */
export class DupLogic {
  private static readonly COMPLETION_KW: string[] = ['完结', '完本', '全本', '全集', '完整', '全套', '全集版'];
  private static readonly FANWAI_RE: RegExp = /^完结\+(\d+(?:\.\d+)?)番外$/;

  /** 复刻核心：计算并持久化应勾选（待删）的 id。 */
  public static async selectDuplicateIds(runId: number): Promise<number[]> {
    const rows: DuplicateRow[] = await ScannedFileDao.getDuplicateRows(runId);
    const subgroups: Map<string, DuplicateRow[]> = new Map<string, DuplicateRow[]>();
    for (const r of rows) {
      const key: string = DupLogic.subKey(r.author, r.title);
      if (!subgroups.has(key)) {
        subgroups.set(key, []);
      }
      subgroups.get(key)!.push(r);
    }
    const allResult: Set<number> = new Set<number>();
    let subgroupsWithDups: number = 0;
    const detailLines: string[] = [];

    for (const [, S] of subgroups) {
      if (S.length < 2) {
        continue;
      }
      const c: Set<number> = new Set<number>(); // 应勾选
      const nc: Set<number> = new Set<number>(); // 永不勾选（保护）
      const fc: Set<number> = new Set<number>(); // 强制勾选（覆盖保护）

      // 规则1：五字段完全相等的精确重复组
      const exact: Map<string, DuplicateRow[]> = new Map<string, DuplicateRow[]>();
      for (const f of S) {
        const key: string = `${f.fileName}\u0000${f.fileSize}\u0000${f.progress.trim()}`;
        if (!exact.has(key)) {
          exact.set(key, []);
        }
        exact.get(key)!.push(f);
      }
      for (const [, g] of exact) {
        if (g.length < 2) {
          continue;
        }
        const newest: DuplicateRow = DupLogic.findNewest(g);
        nc.add(newest.id);
        for (const f of g) {
          if (f.id !== newest.id) {
            c.add(f.id);
            fc.add(f.id);
          }
        }
      }

      // 进度分类
      const numericFiles: DuplicateRow[] = S.filter((f) => DupLogic.progressValue(f.progress) !== null);
      const chineseFiles: DuplicateRow[] = S.filter((f) => DupLogic.hasCjk(f.progress));
      const allNumeric: boolean = numericFiles.length === S.length;

      if (allNumeric) {
        let maxVal: number = -Infinity;
        for (const f of S) {
          maxVal = Math.max(maxVal, DupLogic.progressValue(f.progress)!);
        }
        const maxIds: Set<number> = new Set<number>(
          S.filter((f) => DupLogic.progressValue(f.progress)! === maxVal).map((f) => f.id)
        );
        for (const f of S) {
          if (!maxIds.has(f.id)) {
            c.add(f.id);
          }
        }
        for (const id of maxIds) {
          nc.add(id);
        }
      } else {
        for (const f of chineseFiles) {
          nc.add(f.id);
        }
        if (chineseFiles.length > 0 && numericFiles.length > 0) {
          let maxNumVal: number = -Infinity;
          for (const f of numericFiles) {
            maxNumVal = Math.max(maxNumVal, DupLogic.progressValue(f.progress)!);
          }
          const maxNumFiles: DuplicateRow[] = numericFiles.filter((f) => DupLogic.progressValue(f.progress)! === maxNumVal);
          const hasCompletion: boolean = S.some((cf) => DupLogic.COMPLETION_KW.some((kw) => cf.fileName.includes(kw)));
          let minChineseSize: number = Infinity;
          for (const f of chineseFiles) {
            minChineseSize = Math.min(minChineseSize, f.fileSize);
          }
          if (hasCompletion && maxNumFiles.every((mn) => mn.fileSize < minChineseSize)) {
            for (const f of maxNumFiles) {
              fc.add(f.id);
            }
          }
        }
      }

      // 规则4：本组内唯一文件大小最大者，不勾选
      let maxSize: number = 0;
      for (const f of S) {
        maxSize = Math.max(maxSize, f.fileSize);
      }
      let maxSizeCount: number = 0;
      for (const f of S) {
        if (f.fileSize === maxSize) {
          maxSizeCount++;
        }
      }
      if (maxSizeCount === 1) {
        for (const f of S) {
          if (f.fileSize === maxSize) {
            nc.add(f.id);
          }
        }
      }

      // 规则5：完结+N番外 组合排序去重
      const fanwai: DuplicateRow[] = S.filter((f) => DupLogic.fanwaiValue(f.progress) !== null);
      if (fanwai.length > 0) {
        let maxN: number = -Infinity;
        for (const f of fanwai) {
          maxN = Math.max(maxN, DupLogic.fanwaiValue(f.progress)!);
        }
        const maxNIds: Set<number> = new Set<number>(
          fanwai.filter((f) => DupLogic.fanwaiValue(f.progress)! === maxN).map((f) => f.id)
        );
        for (const f of fanwai) {
          if (maxNIds.has(f.id)) {
            nc.add(f.id);
            fc.delete(f.id);
          } else if (f.fileSize === maxSize) {
            nc.add(f.id);
            fc.delete(f.id);
          } else {
            c.add(f.id);
            fc.add(f.id);
          }
        }
      }

      const subResult: Set<number> = new Set<number>();
      for (const id of c) {
        if (!nc.has(id)) {
          subResult.add(id);
        }
      }
      for (const id of fc) {
        subResult.add(id);
      }

      if (subResult.size > 0) {
        subgroupsWithDups++;
        const nv: string = S[0].title.length === 0 ? '?' : S[0].title;
        const au: string = S[0].author.length === 0 ? '?' : S[0].author;
        const ids: number[] = Array.from(subResult).sort((a, b) => a - b);
        detailLines.push(`标记重复-重复子组 书名=${nv} 作者=${au} 共${S.length}本 -> 勾选${subResult.size}个: ${ids.join(',')}`);
        for (const id of subResult) {
          allResult.add(id);
        }
      }
    }

    LogUtil.i('DupLogic', `标记重复 完成 run=${runId} 重复子组=${subgroupsWithDups} 应勾选=${allResult.size} 个`);
    if (detailLines.length > 0) {
      LogUtil.i('DupLogic', detailLines.join('\n'));
    }
    if (allResult.size > 0) {
      await ScannedFileDao.setCheckedForIds(Array.from(allResult), 1);
    }
    return Array.from(allResult);
  }

  /**
   * 按“书名 + 作者”相同标记重复（文件名解析结果）。
   * 每组保留 id 最小的一条，其余标记 marked=1。
   * 返回本次标记的条数。
   */
  public static async markDuplicatesByName(runId: number): Promise<number> {
    const n: number = await ScannedFileDao.markDuplicatesByNameSql(runId);
    LogUtil.i('DupLogic', `按书名作者标记重复 marked ${n} files (run=${runId})`);
    return n;
  }

  private static findNewest(g: DuplicateRow[]): DuplicateRow {
    let newest: DuplicateRow = g[0];
    for (const f of g) {
      if (f.createdAt > newest.createdAt || (f.createdAt === newest.createdAt && f.id > newest.id)) {
        newest = f;
      }
    }
    return newest;
  }

  private static hasCjk(s: string | null): boolean {
    if (!s || s.length === 0) {
      return false;
    }
    for (let i = 0; i < s.length; i++) {
      const o: number = s.charCodeAt(i);
      if ((o >= 0x4e00 && o <= 0x9fff) || (o >= 0x3400 && o <= 0x4dbf)) {
        return true;
      }
    }
    return false;
  }

  private static progressValue(s: string | null): number | null {
    const t: string = (s ?? '').trim();
    if (t.length === 0 || DupLogic.hasCjk(t)) {
      return null;
    }
    const m: RegExpExecArray | null = /^(\d+(?:\.\d+)?)\s*%?$/.exec(t);
    if (!m) {
      return null;
    }
    const v: number = Number.parseFloat(m[1]);
    return isNaN(v) ? null : v;
  }

  private static fanwaiValue(s: string | null): number | null {
    const t: string = (s ?? '').trim();
    if (t.length === 0) {
      return null;
    }
    const m: RegExpExecArray | null = DupLogic.FANWAI_RE.exec(t);
    if (!m) {
      return null;
    }
    const v: number = Number.parseFloat(m[1]);
    return isNaN(v) ? null : v;
  }

  private static subKey(author: string, title: string): string {
    return `${author.trim().toLowerCase()}\u0000${title.trim().toLowerCase()}`;
  }
}
