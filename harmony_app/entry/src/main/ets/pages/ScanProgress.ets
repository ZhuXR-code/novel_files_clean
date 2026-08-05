import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanConfig } from '../model/ScanConfig';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { ScanService, ScanProgress as ScanProgressData } from '../service/ScanService';
import { AppContext } from '../utils/AppContext';
import { LogUtil } from '../utils/LogUtil';
import { FormatUtil } from '../utils/FormatUtil';
import { TopBar } from '../components/TopBar';
import { ToastUtil } from '../utils/ToastUtil';

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
        // 配置已有目录时直接开始扫描，不再要求用户重新选择路径
        if (this.folderUri.length > 0) {
          this.startScan();
        }
      }
    }
  }

  private async selectDir(): Promise<void> {
    const ctx = AppContext.get();
    if (!ctx) {
      return;
    }
    try {
      const uri = await ScanService.selectDirectory(ctx, this.folderUri);
      if (uri.length === 0) {
        return; // 用户取消选择
      }
      this.folderUri = uri;
      this.folderName = FormatUtil.formatFolderDisplay(uri);
    } catch (e) {
      LogUtil.e('ScanProgress', `选择目录失败: ${(e as Error).message}`);
      ToastUtil.show(`选择失败: ${(e as Error).message}`);
    }
  }

  private async startScan(): Promise<void> {
    if (this.folderUri.length === 0) {
      ToastUtil.show('请先选择扫描目录');
      return;
    }
    // 权限预检（修复「点击扫描提示扫描失败」）：
    // FILE 回退模式（逐文件扫描，每个文件已单独授权）无需目录权限，直接扫描；
    // 目录授权失效时自动弹出重新授权确认框，成功后再继续，而不是直接报扫描失败。
    if (!(ScanService.useFileFallback() || ScanService.restoreFileFallback())) {
      const accessibleUri: string = await ScanService.tryAccessOrReauthorize(getContext(this), this.folderUri);
      if (accessibleUri.length === 0) {
        this.folderName = '';
        ToastUtil.show('扫描目录权限已失效，请重新选择目录');
        return;
      }
      if (accessibleUri !== this.folderUri) {
        this.folderUri = accessibleUri;
        if (this.config) {
          this.config.folderUri = accessibleUri;
        }
      }
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
      // 关键修复：runScan 的进度回调按 PROGRESS_INTERVAL=16 节流，
      // 总数 < 16（如用户的 10 个文件）时回调从未触发，this.found / this.processed
      // 仍停留在初始值 0，导致完成页显示"共扫描到 0 个文件"（数据库 file_count
      // 已被 updateFileCount 正确更新为 10，故文库显示 10 个文件）。
      // 这里用 runScan 返回的最终值兜底刷新 UI。
      this.found = res.total;
      this.processed = res.processed ?? this.processed;
      this.done = true;
      // 推送全局刷新信号，让首页/文库列表在扫描完成后立即显示新文库
      AppStorage.setOrCreate('libraryRefreshTick', Date.now());
    } catch (e) {
      const errMsg: string = (e as Error).message;
      LogUtil.e('ScanProgress', `扫描失败: ${errMsg}`);
      if (errMsg.includes('无法访问扫描目录') || errMsg.includes('Operation not permitted') ||
        errMsg.toLowerCase().includes('permission')) {
        ToastUtil.show('扫描目录不可访问，请重新选择目录');
      } else {
        ToastUtil.show('扫描失败，请查看日志');
      }
    }
    this.scanning = false;
  }

  private openResult(): void {
    router.replaceUrl({ url: 'pages/LibraryScreen', params: { runId: this.resultRunId } }).catch((err: Error) => {
      LogUtil.e('ScanProgress', `跳转失败: ${err.message}`);
    });
  }

  private handleBack(): void {
    if (this.scanning) {
      promptAction.showDialog({
        title: '提示',
        message: '扫描进行中，确认退出？',
        buttons: [
          { text: '继续扫描', color: $r('app.color.text_secondary') },
          { text: '退出', color: $r('app.color.danger') }
        ]
      }).then((result) => {
        if (result.index === 1) {
          ScanService.stop();
          router.back();
        }
      });
    } else {
      router.back();
    }
  }

  onBackPress(): boolean {
    this.handleBack();
    return true;
  }

  build() {
    Column() {
      TopBar({ title: '扫描', onBack: () => this.handleBack() })

      Column({ space: 16 }) {
        if (this.scanning) {
          Text('正在扫描…')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          // 进度指示（扫描时总文件数未知，用旋转加载动画表示进行中）
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.primary'))
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
          Row({ space: 12 }) {
            Button('查看文库')
              .layoutWeight(1)
              .backgroundColor($r('app.color.primary'))
              .onClick(() => this.openResult())
            Button('重新扫描')
              .layoutWeight(1)
              .backgroundColor($r('app.color.bg_card'))
              .fontColor($r('app.color.text_primary'))
              .onClick(() => this.startScan())
          }
          .width('60%')
        } else {
          Text(`目录: ${FormatUtil.formatFolderDisplay(this.folderUri) || this.folderName || '(未选择)'}`)
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
