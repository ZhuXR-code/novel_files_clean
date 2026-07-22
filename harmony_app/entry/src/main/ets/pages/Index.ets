import { router } from '@kit.ArkUI';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct Index {
  @State totalFiles: number = 0;
  @State markedCount: number = 0;
  @State libraryCount: number = 0;
  @State configCount: number = 0;

  async aboutToAppear(): Promise<void> {
    try {
      this.totalFiles = await ScannedFileDao.countAll();
      this.markedCount = await ScannedFileDao.countMarked();
      this.libraryCount = await ScanRunDao.count();
      this.configCount = await ScanConfigDao.count();
    } catch (e) {
      LogUtil.e('Index', `加载统计失败: ${(e as Error).message}`);
    }
  }

  private go(url: string): void {
    router.pushUrl({ url: url }).catch((err: Error) => {
      LogUtil.e('Index', `导航失败 ${url}: ${err.message}`);
    });
  }

  build() {
    Column() {
      Text('文件清理与内容识别')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24, bottom: 16 })

      Row({ space: 12 }) {
        this.statCard('总文件', this.totalFiles.toString())
        this.statCard('已标记', this.markedCount.toString())
      }.margin({ bottom: 12 })

      Row({ space: 12 }) {
        this.statCard('文库', this.libraryCount.toString())
        this.statCard('配置', this.configCount.toString())
      }.margin({ bottom: 20 })

      Column({ space: 12 }) {
        this.navButton('扫描配置', 'pages/ScanConfigList', $r('app.color.primary'))
        this.navButton('文库列表', 'pages/LibraryList', $r('app.color.primary'))
        this.navButton('一键清理', 'pages/OneClickCleanup', $r('app.color.primary'))
        this.navButton('关键词替换', 'pages/KeywordReplace', $r('app.color.primary'))
        this.navButton('操作日志', 'pages/LogViewer', $r('app.color.primary'))
        this.navButton('设置', 'pages/Settings', $r('app.color.primary'))
        this.navButton('帮助', 'pages/Help', $r('app.color.primary'))
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  statCard(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('48%')
    .height(80)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(12)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  navButton(label: string, url: string, color: Resource) {
    Button(label)
      .width('100%')
      .height(48)
      .backgroundColor(color)
      .fontSize(16)
      .onClick(() => this.go(url))
  }
}
