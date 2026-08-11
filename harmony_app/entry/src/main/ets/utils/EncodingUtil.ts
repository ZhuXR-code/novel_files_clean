import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/**
 * 文件编码探测工具，对齐安卓端 EncodingUtil + iOS 端 EncodingUtil.decodeStrict。
 *
 * 探测规则：
 * 1. 先检查 BOM（UTF-8、UTF-16LE、UTF-16BE）；
 * 2. 无 BOM 时按字节校验是否合法 UTF-8，且对采样尾部被截断的不完整多字节序列
 *    视作合法前缀（对齐 iOS/安卓，避免采样边界误判）；
 * 3. 关键修复：引入 decodeStrict（移植自 iOS）做 CJK 占比评分 + 异常字符惩罚，
 *    纠正「GBK 文件被误判为合法 UTF-8 → 用 UTF-8 解码成乱码（损坏文件）」的问题；
 *    并以 GB18030 兜底（中文 txt 常见编码，GBK 超集），失败再回退 GBK。
 *
 * 仅在“深度扫描”模式下调用 detectEncodingName，对齐安卓端 deep 模式才检测编码的语义。
 */
export class EncodingUtil {
  private static readonly SAMPLE_BYTES: number = 16 * 1024;

  /** 探测文件编码显示名：UTF-8 / UTF-16LE / UTF-16BE / GB18030 / GBK。 */
  public static detectEncodingName(uri: string): string {
    let fd: number = 0;
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      fd = file.fd;
      const buf: ArrayBuffer = new ArrayBuffer(EncodingUtil.SAMPLE_BYTES);
      const len: number = fileIo.readSync(fd, buf, { offset: 0, length: EncodingUtil.SAMPLE_BYTES });
      const bytes: Uint8Array = new Uint8Array(buf.slice(0, len));
      return EncodingUtil.detect(bytes);
    } catch (e) {
      return 'UTF-8';
    } finally {
      if (fd !== 0) {
        try {
          fileIo.closeSync(fd);
        } catch (e) {
          // 忽略关闭异常
        }
      }
    }
  }

  private static detect(bytes: Uint8Array): string {
    const len: number = bytes.length;
    if (len >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      return 'UTF-8';
    }
    if (len >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return 'UTF-16LE';
    }
    if (len >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return 'UTF-16BE';
    }
    // 关键修复：用 decodeStrict 严格解码并评分，对齐 iOS：
    // 若 UTF-8 严格解码后 CJK 占比达标且异常字符少，则判 UTF-8；
    // 否则用 GB18030 严格解码评分，谁更"像中文文本"用谁，最后兜底 GBK。
    return EncodingUtil.decodeStrict(bytes);
  }

  /**
   * 严格解码并自动选编码（移植自 iOS decodeStrict，对齐安卓 Charset 严格解码语义）。
   *
   * 修复点：原生 util.TextDecoder 解码非法 UTF-8 时会静默丢弃/替换字节，
   * 造成 GBK 文件被当成 UTF-8 解码后满满乱码（用户感知为"损坏的文件"）。
   * 这里通过 CJK 占比评分 + 异常字符惩罚，在 UTF-8 与 GB18030 之间择优：
   * 数字符层面占比，而非简单"能否解码"。
   *
   * @param bytes 采样字节（建议 ≥ 1KB，越长判定越准）
   * @param prefer 可选，外部已确定主候选（如已知含 BOM 的 UTF-8）；为空则自动评分
   * @returns 显示名：'UTF-8' / 'GB18030' / 'GBK'
   */
  public static decodeStrict(bytes: Uint8Array, prefer?: string): string {
    if (!bytes || bytes.length === 0) {
      return prefer && prefer.length > 0 ? prefer : 'UTF-8';
    }

    // 候选口径（对齐安卓 GB18030 优先）：Utf8 → Gb18030 → Gbk
    const utfText: string = EncodingUtil.decodeBytes(bytes, 'utf-8');
    const gbText: string = EncodingUtil.decodeBytes(bytes, 'gb18030');
    const gbkText: string = EncodingUtil.decodeBytes(bytes, 'gbk');

    if (!utfText) {
      // UTF-8 严格解码完全失败（含非法序列），直接用 GB18030（含 GBK 字符集）
      return gbkText && gbkText.length > 0 ? 'GB18030' : 'GBK';
    }

    const utfScore: number = EncodingUtil.scoreText(utfText);

    // 已指定主候选：该候选解码成功且评分达标即采用；否则落回自动评分
    if (prefer && prefer.length > 0) {
      if (prefer.toUpperCase() === 'UTF-8') {
        if (utfScore >= 0.4) return 'UTF-8';
      } else {
        const pText: string = EncodingUtil.decodeBytes(bytes, prefer.toLowerCase());
        if (pText && EncodingUtil.scoreText(pText) > utfScore) {
          return prefer.toUpperCase();
        }
      }
    }

    // 自动评分：GB18030 与 UTF-8 二选一
    const gbScore: number = EncodingUtil.scoreText(gbText);
    if (gbScore > utfScore && gbScore >= 0.4) {
      return 'GB18030';
    }
    return 'UTF-8';
  }

  /**
   * 文本"像中文文本"的评分（移植自 iOS cjkScore）：
   * - CJK 统一表意文字（含扩展区）占比越高越好；
   * - 异常字符（U+FFFD 替换符、孤立控制字符、孤立代理项）越多越像损坏乱码，扣分。
   */
  private static scoreText(text: string): number {
    if (!text || text.length === 0) return 0;
    let cjk: number = 0;
    let abnormal: number = 0;
    const n: number = text.length;
    for (let i = 0; i < n; i++) {
      const cp: number = text.charCodeAt(i);
      // 先归一化到码点（处理 UTF-16 代理对）
      let code: number = cp;
      if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n) {
        const lo: number = text.charCodeAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          code = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          i++;
        }
      }
      if (
        (code >= 0x4E00 && code <= 0x9FFF) ||   // CJK 统一表意文字
        (code >= 0x3400 && code <= 0x4DBF) ||   // 扩展 A
        (code >= 0x20000 && code <= 0x2A6DF) || // 扩展 B
        (code >= 0x2A700 && code <= 0x2B73F) || // 扩展 C/D
        (code >= 0xF900 && code <= 0xFAFF)      // 兼容汉字
      ) {
        cjk++;
      } else if (
        cp === 0xFFFD ||                        // U+FFFD 替换字符（解码失败标记）
        (cp >= 0x80 && cp <= 0x9F) ||           // C1 控制字符（乱码常见）
        (cp >= 0x202E && cp <= 0x202F)          // 右向标记等隐式控制字符
      ) {
        abnormal++;
      }
    }
    const cjkRatio: number = cjk / n;
    const abnormalRatio: number = abnormal / n;
    // CJK 占比越高越好；异常字符占比直接惩罚（最多扣到 0）
    return Math.max(0, cjkRatio - abnormalRatio * 2.0);
  }

  /** 安全解码：失败返回空串（不抛异常）。 */
  private static decodeBytes(bytes: Uint8Array, enc: string): string {
    try {
      const decoder: util.TextDecoder = new util.TextDecoder(enc);
      return decoder.decodeToString(bytes);
    } catch {
      return '';
    }
  }

  /** 字节校验是否像 UTF-8（对齐 iOS/安卓：采样尾部不完整序列视为合法前缀）。 */
  private static looksLikeUtf8(bytes: Uint8Array): boolean {
    const len: number = bytes.length;
    let i: number = 0;
    while (i < len) {
      const b: number = bytes[i];
      if (b < 0x80) {
        i++;
      } else if ((b & 0xe0) === 0xc0) {
        // 2 字节序列：续字节越界说明是采样截断的不完整前缀，视为合法（对齐 iOS/安卓）
        if (i + 1 >= len) {
          return true;
        }
        if ((bytes[i + 1] & 0xc0) !== 0x80) {
          return false;
        }
        i += 2;
      } else if ((b & 0xf0) === 0xe0) {
        // 3 字节序列
        if (i + 2 >= len) {
          return true;
        }
        if ((bytes[i + 1] & 0xc0) !== 0x80 || (bytes[i + 2] & 0xc0) !== 0x80) {
          return false;
        }
        i += 3;
      } else if ((b & 0xf8) === 0xf0) {
        // 4 字节序列
        if (i + 3 >= len) {
          return true;
        }
        if ((bytes[i + 1] & 0xc0) !== 0x80 || (bytes[i + 2] & 0xc0) !== 0x80 || (bytes[i + 3] & 0xc0) !== 0x80) {
          return false;
        }
        i += 4;
      } else {
        return false;
      }
    }
    return true;
  }
}
