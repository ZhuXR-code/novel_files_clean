import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { ScannedFile } from '../model/ScannedFile';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { ToastUtil } from '../utils/ToastUtil';

@Entry
@Component
struct FileDetail {
  @State fileId: number = 0;
  @State file: ScannedFile | null = null;
  @State loading: boolean = true;
  // 对齐安卓端：预览范围选择弹窗（前50行/全部内容）
  @State showPreviewChoice: boolean = false;
  // 对齐安卓端：删除选项弹窗（仅记录/记录+源文件）
  @State showDeleteChoice: boolean = false;
  @State deleteSource: boolean = false;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['fileId'] !== undefined && params['fileId'] !== null) {
      this.fileId = params['fileId'] as number;
    }
    try {
      this.file = await ScannedFileDao.getById(this.fileId);
    } catch (e) {
      LogUtil.e('FileDetail', `加载文件详情失败: ${(e as Error).message}`);
      ToastUtil.show('加载失败');
    }
    this.loading = false;
  }

  private async onMarkChanged(marked: boolean): Promise<void> {
    if (!this.file) {
      return;
    }
    try {
      this.file.marked = marked ? 1 : 0;
      await ScannedFileDao.updateMarked(this.file.id, this.file.marked);
    } catch (e) {
      LogUtil.e('FileDetail', `标记失败: ${(e as Error).message}`);
      ToastUtil.show('操作失败');
      this.file.marked = marked ? 0 : 1;
    }
  }

  private async onCheckChanged(checked: boolean): Promise<void> {
    if (!this.file) {
      return;
    }
    try {
      this.file.checked = checked ? 1 : 0;
      await ScannedFileDao.updateChecked(this.file.id, this.file.checked);
    } catch (e) {
      LogUtil.e('FileDetail', `勾选失败: ${(e as Error).message}`);
      ToastUtil.show('操作失败');
      this.file.checked = checked ? 0 : 1;
    }
  }

  // 对齐安卓端：删除前弹窗选择模式（仅记录 / 记录+源文件）
  private deleteThis(): void {
    if (!this.file) {
      return;
    }
    this.showDeleteChoice = true;
  }

  private confirmDelete(): void {
    if (!this.file) {
      return;
    }
    this.showDeleteChoice = false;
    router.pushUrl({
      url: 'pages/DeleteConfirm',
      params: { runId: this.file.scanRunId, fileIds: [this.file.id], deleteSource: this.deleteSource }
    }).catch((err: Error) => {
      LogUtil.e('FileDetail', `跳转失败: ${err.message}`);
    });
  }

  // 对齐安卓端：预览前弹窗选择范围（前50行 / 全部内容）
  private previewContent(): void {
    if (!this.file) {
      return;
    }
    this.showPreviewChoice = true;
  }

  private startPreview(mode: string): void {
    if (!this.file) {
      return;
    }
    this.showPreviewChoice = false;
    router.pushUrl({
      url: 'pages/FilePreview',
      params: {
        fileName: this.file.fileName,
        filePath: this.file.path,
        previewMode: mode
      }
    }).catch((err: Error) => {
      LogUtil.e('FileDetail', `跳转预览失败: ${err.message}`);
    });
  }

  // E组 #17 用系统应用打开文件（适合 pdf/epub/mobi 等非 txt 格式）
  private openFile(): void {
    if (!this.file) {
      return;
    }
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: this.file.path,
        type: FileDetail.extToMime(this.file.ext)
      };
      ctx.startAbility(want).then(() => {
        LogUtil.operation('打开文件', `文件=${this.file!.fileName}`);
      }).catch((err: Error) => {
        LogUtil.e('FileDetail', `打开文件失败: ${err.message}`);
        ToastUtil.show('暂无应用可打开此文件，请使用预览查看');
      });
    } catch (e) {
      LogUtil.e('FileDetail', `打开文件异常: ${(e as Error).message}`);
      ToastUtil.show('打开失败，请使用预览查看');
    }
  }

  /** 扩展名 → MIME 映射（常见文本/电子书格式）。 */
  private static extToMime(ext: string): string {
    const e: string = (ext ?? '').toLowerCase();
    switch (e) {
      case 'txt': return 'text/plain';
      case 'pdf': return 'application/pdf';
      case 'epub': return 'application/epub+zip';
      case 'mobi': return 'application/x-mobipocket-ebook';
      case 'azw3': return 'application/x-mobipocket-ebook';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'fb2': return 'application/x-fictionbook+xml';
      case 'html':
      case 'htm': return 'text/html';
      default: return '*/*';
    }
  }

  build() {
    Column() {
      TopBar({ title: '文件详情', rightText: '预览', onRight: () => this.previewContent() })

      if (this.file) {
        Scroll() {
          Column({ space: 8 }) {
            // 主要信息：书名、作者、原文件名（各占一行，对齐安卓 DetailRow）
            this.infoRow('书名', this.file!.title || '(未解析)')
            this.infoRow('作者', this.file!.author || '(未解析)')
            this.infoRow('原文件名', this.file!.fileName)
            // 扩展名 + 大小 + 编码（三列一行，对齐安卓 DetailRowColumns）
            this.infoRow3(
              '扩展名', this.file!.ext || '(无)',
              '大小', FormatUtil.formatFileSize(this.file!.fileSize),
              '编码', this.file!.encoding || '(未检测)'
            )
            // 进度 + 来源 + 日期（三列一行）
            this.infoRow3(
              '进度', this.file!.progress || '(未解析)',
              '来源', this.file!.source || '(未解析)',
              '修改时间', FormatUtil.formatFileDate(this.file!.fileDate)
            )
            // 星标 + 勾选（两列一行，带 Toggle 开关）
            Row() {
              Column({ space: 4 }) {
                Text('星标')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Toggle({ type: ToggleType.Switch, isOn: this.file!.marked === 1 }).onChange((v: boolean) => this.onMarkChanged(v))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column({ space: 4 }) {
                Text('勾选删除')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Toggle({ type: ToggleType.Switch, isOn: this.file!.checked === 1 }).onChange((v: boolean) => this.onCheckChanged(v))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_card'))
            .borderRadius(8)
            .padding(12)

            // 路径（单独一行，可复制）
            this.infoRow('路径', this.file!.path)
            // 扫描时间（单独一行）
            this.infoRow('扫描时间', FormatUtil.formatTimestamp(this.file!.createdAt))

            // 操作按钮
            Button('删除此文件')
              .width('100%')
              .height(44)
              .backgroundColor($r('app.color.danger'))
              .fontColor($r('app.color.text_on_primary'))
              .margin({ top: 12 })
              .onClick(() => this.deleteThis())
            // E组 #17 用系统应用打开文件
            Button('打开文件')
              .width('100%')
              .height(44)
              .backgroundColor($r('app.color.bg_light'))
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 8 })
              .onClick(() => this.openFile())
          }
          .width('100%')
          .padding(16)
        }
        .layoutWeight(1)
        .width('100%')
      }

      // 预览范围选择弹窗（对齐安卓端：前50行/全部内容）
      if (this.showPreviewChoice) {
        this.previewChoiceDialog()
      }

      // 删除选项弹窗（对齐安卓端：仅记录/记录+源文件）
      if (this.showDeleteChoice) {
        this.deleteChoiceDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  // 预览范围选择弹窗
  @Builder
  previewChoiceDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => { this.showPreviewChoice = false; })

      Column({ space: 12 }) {
        Text('预览范围')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Button('前50行（快速预览）')
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.bg_page'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.startPreview('head'))

        Button('全部内容（完整加载）')
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.text_on_primary'))
          .onClick(() => this.startPreview('full'))

        Button('后100行（查看末尾）')
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.bg_page'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.startPreview('tail'))

        Button('取消')
          .width('100%')
          .height(40)
          .backgroundColor($r('app.color.bg_page'))
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => { this.showPreviewChoice = false; })
      }
      .width('85%')
      .padding(16)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      // 弹窗卡片居中：position + markAnchor 实现真正的中心对齐
      .position({ x: '50%', y: '50%' })
      .markAnchor({ x: '50%', y: '50%' })
    }
    .width('100%')
    .height('100%')
  }

  // 删除选项弹窗
  @Builder
  deleteChoiceDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => { this.showDeleteChoice = false; })

      Column({ space: 12 }) {
        Text('删除选择')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Row() {
          Radio({ value: 'record', group: 'fdDeleteChoice' })
            .checked(!this.deleteSource)
            .onChange((isOn: boolean) => { if (isOn) this.deleteSource = false; })
          Column({ space: 2 }) {
            Text('仅删除记录')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Text('只删除数据库中的扫描记录，保留源文件')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .margin({ left: 8 })
          .layoutWeight(1)
        }
        .width('100%')
        .onClick(() => { this.deleteSource = false; })

        Row() {
          Radio({ value: 'source', group: 'fdDeleteChoice' })
            .checked(this.deleteSource)
            .onChange((isOn: boolean) => { if (isOn) this.deleteSource = true; })
          Column({ space: 2 }) {
            Text('删除记录和源文件')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Text('同时删除数据库记录和磁盘上的源文件（不可恢复）')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .margin({ left: 8 })
          .layoutWeight(1)
        }
        .width('100%')
        .onClick(() => { this.deleteSource = true; })

        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_page'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => { this.showDeleteChoice = false; })
          Button('确认删除')
            .layoutWeight(1)
            .backgroundColor($r('app.color.danger'))
            .fontColor($r('app.color.text_on_primary'))
            .onClick(() => this.confirmDelete())
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('85%')
      .padding(16)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      // 弹窗卡片居中：position + markAnchor 实现真正的中心对齐
      .position({ x: '50%', y: '50%' })
      .markAnchor({ x: '50%', y: '50%' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  infoRow(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .copyOption(CopyOptions.InApp)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(8)
    .padding(12)
  }

  // 三列信息行（对齐安卓 DetailRowColumns）：扩展名/大小/编码 等
  @Builder
  infoRow3(label1: string, value1: string, label2: string, value2: string, label3: string, value3: string) {
    Row() {
      Column({ space: 4 }) {
        Text(label1)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(value1)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text(label2)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(value2)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text(label3)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(value3)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(8)
    .padding(12)
  }
}
