import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { DeleteService } from '../service/DeleteService';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct DeleteProgress {
  @State runId: number = 0;
  @State ids: number[] = [];
  @State deleting: boolean = false;
  @State done: boolean = false;
  @State deleted: number = 0;
  @State failed: number = 0;
  @State pDone: number = 0;
  @State pTotal: number = 0;
  @State currentFile: string = '';
  @State deleteSource: boolean = true;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['runId'] !== undefined && params['runId'] !== null) {
      this.runId = params['runId'] as number;
    }
    if (params && params['ids'] !== undefined && params['ids'] !== null) {
      this.ids = params['ids'] as number[];
    }
    if (params && params['deleteSource'] !== undefined && params['deleteSource'] !== null) {
      this.deleteSource = params['deleteSource'] as boolean;
    }
    this.pTotal = this.ids.length;
  }

  private async startDelete(): Promise<void> {
    if (this.deleting || this.done) {
      return;
    }
    this.deleting = true;
    try {
      const res = await DeleteService.deleteByIds(this.ids, {
        deleteSource: this.deleteSource,
        onProgress: (d: number, total: number, success: number, failed: number, c: string) => {
          this.pDone = d;
          this.pTotal = total;
          this.deleted = success;
          this.failed = failed;
          this.currentFile = c;
        }
      });
      this.deleted = res.deleted;
      this.failed = res.failed;
      this.done = true;
    } catch (e) {
      LogUtil.e('DeleteProgress', `删除失败: ${(e as Error).message}`);
      promptAction.showToast({ message: '删除异常' });
    }
    this.deleting = false;
  }

  private finish(): void {
    router.replaceUrl({ url: 'pages/LibraryScreen', params: { runId: this.runId } }).catch((err: Error) => {
      LogUtil.e('DeleteProgress', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('删除中')
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
        if (this.deleting) {
          Text('正在删除…')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text(`进度: ${this.pDone} / ${this.pTotal}`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text(`当前: ${this.currentFile}`)
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        } else if (this.done) {
          Text('删除完成')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.success'))
          Text(`成功: ${this.deleted}   失败: ${this.failed}`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          if (this.failed > 0) {
            Text('失败多为 Picker 授权失效，可在原目录重新授权后重试')
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))
              .padding({ left: 16, right: 16 })
              .lineHeight(18)
          }
          Button('完成')
            .width('60%')
            .backgroundColor($r('app.color.primary'))
            .onClick(() => this.finish())
        } else {
          Text(`将删除 ${this.ids.length} 个文件`)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text(this.deleteSource ? '模式：删除数据库记录 + 物理源文件' : '模式：仅删除数据库记录，保留物理源文件')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Button('开始删除')
            .width('60%')
            .backgroundColor($r('app.color.danger'))
            .onClick(() => this.startDelete())
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
