import { fileIo, picker } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { AppContext } from '../utils/AppContext';
import { LogUtil } from '../utils/LogUtil';

/**
 * 书库/合集列表「导出为 TXT」的落盘服务。
 *
 * 与 ExportService（导出 CSV 到应用沙箱 filesDir）不同，这里用系统 DocumentViewPicker.save()
 * 让用户自行选择保存位置，导出的文件用户可在文件管理器中直接看到、分享。
 */
export class ListExportService {
  /**
   * 弹出系统「另存为」选择保存位置并写入文本内容。
   *
   * @param content 完整 TXT 文本
   * @param defaultName 默认文件名（如 书库列表_20260802_143012.txt）
   * @returns 实际保存的文件名；用户取消返回空串
   */
  public static async saveAsTxt(content: string, defaultName: string): Promise<string> {
    const ctx = AppContext.get();
    if (!ctx) {
      throw new Error('AppContext 未初始化');
    }

    // 1) 让用户选择保存位置，拿到可写 URI
    const documentPicker = new picker.DocumentViewPicker(ctx);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [defaultName];
    options.fileSuffixChoices = ['.txt'];
    const uris: string[] = await documentPicker.save(options);
    if (!uris || uris.length === 0) {
      // 用户取消
      return '';
    }
    const uri: string = uris[0];

    // 2) 写入内容。带 UTF-8 BOM，Windows 记事本/Excel 打开中文不乱码。
    const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bom: Uint8Array = new Uint8Array([0xEF, 0xBB, 0xBF]);
      await fileIo.write(file.fd, bom.buffer as ArrayBuffer);
      const body: ArrayBuffer = buffer.from(content, 'utf-8').buffer as ArrayBuffer;
      await fileIo.write(file.fd, body);
    } finally {
      await fileIo.close(file);
    }

    LogUtil.i('ListExportService', `导出列表完成: ${defaultName}`);
    return defaultName;
  }
}
