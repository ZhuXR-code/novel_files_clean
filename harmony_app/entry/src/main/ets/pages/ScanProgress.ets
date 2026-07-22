import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanConfig } from '../model/ScanConfig';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { ScanService, ScanProgress as ScanProgressData } from '../service/ScanService';
import { AppContext } from '../utils/AppContext';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct ScanProgress {
  @State configId: number = 0;
  @State config: ScanConfig | null = null;
  @State folderUri: string = '';
  @State folderName: string = '';
  @State scanning: boolean = false;
  @State processed: number = 0;
  @State found: number = 0;
  @State current: string = '';
  @State done: boolean = false;
  @State stopped: boolean = false;
  @State resultRunId: number = 0;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['configId'] !== undefined && params['configId'] !== null) {
      this.configId = params['configId'] as number;
      this.config = await ScanConfigDao.getById(this.configId);
      if (this.config) {
        this.folderUri = this.config.folderUri;
        this.folderName = this.config.folderName;
      }
    }
  }

  private async selectDir(): Promise<void> {
    const ctx = AppContext.get();
    if (!ctx) {
      return;
    }
    try {
      const uri = await ScanService.selectDirectory(ctx);
      this.folderUri = uri;
      this.folderName = uri.substring(uri.lastIndexOf('/') + 1);
    } catch (e) {
      LogUtil.e('ScanProgress', `选择目录失败: ${(e as Error).message}`);
    }
  }

  private async startScan(): Promise<void> {
    if (this.folderUri.length === 0) {
      promptAction.showToast({ message: '请先选择扫描目录' });
      return;
    }
    const cfg: ScanConfig = this.config ?? new ScanConfig();
    cfg.folderUri = this.folderUri;
    cfg.folderName = this.folderName;
    if (!cfg.name || cfg.name.length === 0) {
      cfg.name = this.folderName || '扫描';
    }
    if (!cfg.fileTypes || cfg.fileTypes.length === 0) {
      cfg.fileTypes = 'txt';
    }
    this.scanning = true;
    this.processed = 0;
    this.found = 0;
    this.current = '';
    this.done = false;
    try {
      const res = await ScanService.runScan(cfg, (p: ScanProgressData) => {
        this.processed = p.processed;
        this.found = p.found;
        this.current = p.currentFile;
      });
      this.resultRunId = res.runId;
      this.stopped = res.stopped;
      this.done = true;
    } catch (e) {
      LogUtil.e('ScanProgress', `扫描失败: ${(e as Error).message}`);
      promptAction.showToast({ message: '扫描失败，请查看日志' });
    }
    this.scanning = false;
  }

  private openResult(): void {
    router.replaceUrl({ url: 'pages/LibraryScreen', params: { runId: this.resultRunId } }).catch((err: Error) => {
      LogUtil.e('ScanProgress', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('扫描')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
        Button('').width(0).height(0).visibility(Visibility.Hidden)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Column({ space: 16 }) {
        if (this.scanning) {
          Text('正在扫描…')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text(`已处理: ${this.processed}  命中: ${this.found}`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text(`当前: ${this.current}`)
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Button('停止扫描')
            .width('60%')
            .backgroundColor($r('app.color.danger'))
            .onClick(() => ScanService.stop())
        } else if (this.done) {
          Text(this.stopped ? '扫描已停止' : '扫描完成')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.stopped ? $r('app.color.text_secondary') : $r('app.color.success'))
          Text(this.stopped ? `已处理 ${this.processed} 个文件，保留命中 ${this.found} 个` : `共扫描到 ${this.found} 个文件`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Button('查看文库')
            .width('60%')
            .backgroundColor($r('app.color.primary'))
            .onClick(() => this.openResult())
        } else {
          Text(`目录: ${this.folderName || '(未选择)'}`)
            .fontSize(15)
            .fontColor(this.folderName ? $r('app.color.text_primary') : $r('app.color.text_hint'))
          Button('选择目录')
            .width('60%')
            .backgroundColor($r('app.color.primary'))
            .onClick(() => this.selectDir())
          Button('开始扫描')
            .width('60%')
            .backgroundColor($r('app.color.primary_dark'))
            .onClick(() => this.startScan())
        }
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
