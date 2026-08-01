import { fileIo } from '@kit.CoreFileKit';

/**
 * 文件编码探测工具，对齐安卓端 EncodingUtil。
 *
 * 探测规则：
 * 1. 先检查 BOM（UTF-8、UTF-16LE、UTF-16BE）；
 * 2. 无 BOM 时按字节校验是否合法 UTF-8；
 * 3. 不是合法 UTF-8 则按 GB18030 兜底（中文 txt 常见编码）。
 *
 * 仅在“深度扫描”模式下调用，对齐安卓端 deep 模式才检测编码的语义。
 */
export class EncodingUtil {
  private static readonly SAMPLE_BYTES: number = 8 * 1024;

  /** 探测文件编码显示名：UTF-8 / UTF-16LE / UTF-16BE / GB18030。 */
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
    return EncodingUtil.looksLikeUtf8(bytes) ? 'UTF-8' : 'GB18030';
  }

  private static looksLikeUtf8(bytes: Uint8Array): boolean {
    const len: number = bytes.length;
    let i: number = 0;
    while (i < len) {
      const b: number = bytes[i];
      if (b < 0x80) {
        i++;
      } else if ((b & 0xe0) === 0xc0) {
        if (i + 1 >= len || (bytes[i + 1] & 0xc0) !== 0x80) {
          return false;
        }
        i += 2;
      } else if ((b & 0xf0) === 0xe0) {
        if (i + 2 >= len || (bytes[i + 1] & 0xc0) !== 0x80 || (bytes[i + 2] & 0xc0) !== 0x80) {
          return false;
        }
        i += 3;
      } else if ((b & 0xf8) === 0xf0) {
        if (i + 3 >= len || (bytes[i + 1] & 0xc0) !== 0x80 || (bytes[i + 2] & 0xc0) !== 0x80 || (bytes[i + 3] & 0xc0) !== 0x80) {
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
