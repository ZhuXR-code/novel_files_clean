import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanConfig } from '../model/ScanConfig';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { ScanRunDao } from '../database/ScanRunDao';
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
  @State excludedCount: number = 0;
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
        // 配置已有目录时直接开始扫描；文件回退模式（folderUri 为空但有已选文件）也直接开始
        if (this.folderUri.length > 0 || ScanService.restoreFileFallback()) {
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
      const result = await ScanService.selectDirectory(ctx, this.folderUri);
      if (result.uri.length === 0 && !result.isFileFallback) {
        return; // 用户取消选择
      }
      if (result.isFileFallback) {
        // 文件回退模式：folderUri 留空走逐文件扫描，界面上显示父文件夹名
        this.folderUri = '';
        this.folderName = result.displayName || FormatUtil.getParentFolderDisplay(result.uri);
        if (this.config) {
          this.config.folderUri = '';
          this.config.folderName = this.folderName;
          // 修复：选择结果立即写库。此前仅改内存对象，startScan 的写回条件
          // (config.folderUri !== folderUri) 因两者已被同步成相等而永不触发，
          // 导致重进扫描页总是需要重新选择目录。
          await this.persistConfig();
        }
        ToastUtil.show('已通过所选文件定位扫描范围');
      } else {
        this.folderUri = result.uri;
        this.folderName = FormatUtil.formatFolderDisplay(result.uri);
        if (this.config) {
          this.config.folderUri = this.folderUri;
          this.config.folderName = this.folderName;
          await this.persistConfig();
        }
      }
    } catch (e) {
      LogUtil.e('ScanProgress', `选择目录失败: ${(e as Error).message}`);
      ToastUtil.show(`选择失败: ${(e as Error).message}`);
    }
  }

  /** 将当前内存中的配置（目录 URI/名称等）写回数据库，失败仅记日志不阻断扫描。 */
  private async persistConfig(): Promise<void> {
    if (!this.config) {
      return;
    }
    try {
      await ScanConfigDao.update(this.config);
    } catch (e) {
      LogUtil.e('ScanProgress', `保存扫描配置失败: ${(e as Error).message}`);
    }
  }

  private async startScan(): Promise<void> {
    const hasFileFallback: boolean = ScanService.useFileFallback();
    if (this.folderUri.length === 0 && !hasFileFallback) {
      ToastUtil.show('请先选择扫描目录');
      return;
    }
    // 权限预检（修复「点击扫描提示扫描失败」）：
    // 目录模式（folderUri 非空）才需要校验目录访问权限；FILE 回退模式
    // （folderUri 为空，selectedFileUris 承载已授权文件）无需目录权限，直接扫描。
    // 注意：目录模式下不要调用 restoreFileFallback()，否则会把 Preferences 里
    // 历史残留的文件 URI 读回内存，污染本次目录扫描的目标。
    if (this.folderUri.length > 0) {
      const accessibleUri: string = await ScanService.tryAccessOrReauthorize(AppContext.get(), this.folderUri);
      if (accessibleUri.length === 0) {
        // 权限彻底失效（持久化/重新授权均失败，常见于模拟器重启或重装后）。
        // 弹窗引导用户重新选择目录，比直接提示失败更友好。
        this.folderName = '';
        const dialogRes: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
          title: '目录权限已失效',
          message: '鸿蒙系统出于安全限制，应用无法自行恢复已过期的目录授权，'
            + '需通过系统文件选择器由你重新确认。\n请重新选择扫描目录（选择原目录即可）。',
          buttons: [
            { text: '取消', color: $r('app.color.text_secondary') },
            { text: '重新选择', color: $r('app.color.primary') }
          ]
        });
        if (dialogRes.index !== 1) {
          return; // 用户取消
        }
        await this.selectDir();
        // 文件回退模式下 folderUri 故意为空（扫描目标在 selectedFileUris），不能仅用 folderUri 判空
        if (this.folderUri.length === 0 && !ScanService.useFileFallback()) {
          return; // 用户未选择新目录
        }
      } else if (accessibleUri !== this.folderUri) {
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
    // 重新授权/重新选择后目录 URI 可能已变化：写回数据库，避免下次使用旧配置再次失效
    if (this.config && this.config.folderUri !== this.folderUri) {
      this.config.folderUri = this.folderUri;
      try {
        await ScanConfigDao.update(this.config);
      } catch (e) {
        LogUtil.e('ScanProgress', `保存新目录 URI 失败: ${(e as Error).message}`);
      }
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
        if (p.excluded !== undefined) { this.excludedCount = p.excluded; }
        this.current = p.currentFile;
      });
      this.resultRunId = res.runId;
      this.stopped = res.stopped;
      // 用 runScan 返回值兜底刷新 UI（进度回调按 PROGRESS_INTERVAL=16 节流，
      // 小量文件时可能从未触发回调）
      this.found = res.total;
      this.processed = res.processed ?? this.processed;
      this.excludedCount = res.excluded ?? this.excludedCount;
      this.done = true;
      // 扫描完成后把文件数写回 scan_run.file_count，否则首页「最近文库」会始终显示 0。
      try {
        await ScanRunDao.updateFileCount(res.runId, res.total);
      } catch (e) {
        LogUtil.e('ScanProgress', `更新文库文件数失败: ${(e as Error).message}`);
      }
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

  private buildSummaryText(): string {
    const excl: number = this.excludedCount;
    if (this.stopped) {
      return `已处理 ${this.processed} 个文件，保留命中 ${this.found} 个`;
    }
    return (excl > 0)
      ? `共解析 ${this.found} 个文件（已排除 ${excl} 个）`
      : `共解析 ${this.found} 个文件`;
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
            .backgroundColor($r('app.color.btn_danger_bg'))
            .onClick(() => ScanService.stop())
        } else if (this.done) {
          Text(this.stopped ? '扫描已停止' : '扫描完成')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.stopped ? $r('app.color.text_secondary') : $r('app.color.success'))
          Text(this.buildSummaryText())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Row({ space: 12 }) {
            Button('查看文库')
              .layoutWeight(1)
              .backgroundColor($r('app.color.btn_primary_bg'))
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
            .backgroundColor($r('app.color.btn_primary_bg'))
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
