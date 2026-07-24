import { router } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LogUtil } from '../utils/LogUtil';

const PREVIEW_BYTES_LIMIT = 2 * 1024 * 1024;
const INITIAL_LINES = 200;
const LOAD_MORE_LINES = 200;

@Entry
@Component
struct FilePreview {
  @State fileName: string = '';
  @State filePath: string = '';
  @State loading: boolean = true;
  @State lines: string[] = [];
  @State displayCount: number = 0;
  @State encoding: string = 'UTF-8';
  @State firstVisibleIndex: number = 0;
  @State scrollbarTrackHeight: number = 0;
  @State dragStartY: number = 0;

  private scroller: Scroller = new Scroller();

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    this.fileName = (params['fileName'] as string) || '';
    this.filePath = (params['filePath'] as string) || '';
    await this.loadContent();
  }

  async loadContent(): Promise<void> {
    if (!this.filePath) {
      this.loading = false;
      return;
    }
    try {
      const file: fileIo.File = fileIo.openSync(this.filePath, fileIo.OpenMode.READ_ONLY);
      try {
        const stat: fileIo.Stat = fileIo.statSync(this.filePath);
        const toRead: number = Math.min(stat.size, PREVIEW_BYTES_LIMIT);
        if (toRead <= 0) {
          this.loading = false;
          return;
        }
        const buf: ArrayBuffer = new ArrayBuffer(toRead);
        fileIo.readSync(file.fd, buf);
        const bytes: Uint8Array = new Uint8Array(buf.slice(0, toRead));

        let text: string = '';
        if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
          text = this.decodeBytes(bytes.slice(3), 'utf-8');
          this.encoding = 'UTF-8\u2009BOM';
        } else if (this.isValidUtf8(bytes)) {
          text = this.decodeBytes(bytes, 'utf-8');
          this.encoding = 'UTF-8';
        } else {
          text = this.decodeBytes(bytes, 'gbk');
          if (text.length === 0) {
            text = this.decodeBytes(bytes, 'utf-8');
            this.encoding = 'UTF-8';
          } else {
            this.encoding = 'GBK';
          }
        }

        this.lines = text.split('\n').map((l: string) => l.replace(/\r$/, ''));
        this.displayCount = Math.min(this.lines.length, INITIAL_LINES);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      LogUtil.e('FilePreview', `读取失败: ${(e as Error).message}`);
    }
    this.loading = false;
  }

  private decodeBytes(bytes: Uint8Array, enc: string): string {
    try {
      const decoder: util.TextDecoder = new util.TextDecoder(enc);
      return decoder.decodeToString(bytes);
    } catch {
      return '';
    }
  }

  private isValidUtf8(bytes: Uint8Array): boolean {
    let i: number = 0;
    while (i < bytes.length) {
      const b: number = bytes[i];
      if (b <= 0x7F) {
        i++;
      } else if (b >= 0xC2 && b <= 0xDF) {
        if (i + 1 >= bytes.length || (bytes[i + 1] & 0xC0) !== 0x80) return false;
        i += 2;
      } else if (b === 0xE0) {
        if (i + 2 >= bytes.length || bytes[i + 1] < 0xA0 || bytes[i + 1] > 0xBF ||
          (bytes[i + 2] & 0xC0) !== 0x80) return false;
        i += 3;
      } else if (b >= 0xE1 && b <= 0xEF) {
        if (i + 2 >= bytes.length || (bytes[i + 1] & 0xC0) !== 0x80 ||
          (bytes[i + 2] & 0xC0) !== 0x80) return false;
        i += 3;
      } else if (b === 0xF0) {
        if (i + 3 >= bytes.length || bytes[i + 1] < 0x90 || bytes[i + 1] > 0xBF ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else if (b >= 0xF1 && b <= 0xF3) {
        if (i + 3 >= bytes.length || (bytes[i + 1] & 0xC0) !== 0x80 ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else if (b >= 0xF4 && b <= 0xF7) {
        if (i + 3 >= bytes.length || bytes[i + 1] < 0x80 || bytes[i + 1] > 0x8F ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else {
        return false;
      }
    }
    return true;
  }

  private loadMore(): void {
    this.displayCount = Math.min(this.displayCount + LOAD_MORE_LINES, this.lines.length);
  }

  get getLoadedAll(): boolean {
    return this.displayCount >= this.lines.length;
  }

  get getThumbHeight(): number {
    const trackH: number = this.scrollbarTrackHeight;
    if (trackH <= 0 || this.lines.length <= 0) return 40;
    const ratio: number = this.displayCount / this.lines.length;
    return Math.max(trackH * ratio, 30);
  }

  get getThumbOffset(): number {
    const trackH: number = this.scrollbarTrackHeight;
    const thumbH: number = this.getThumbHeight;
    const remaining: number = this.lines.length - this.displayCount;
    if (trackH <= 0 || remaining <= 0 || this.displayCount <= 0) return 0;
    const ratio: number = this.firstVisibleIndex / remaining;
    return Math.max(0, Math.min(ratio * (trackH - thumbH), trackH - thumbH));
  }

  build() {
    Column() {
      Row() {
        Button('返回').fontSize(15).onClick(() => router.back())
        Text(this.fileName)
          .fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          .textAlign(TextAlign.Center).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%').height(56).padding({ left: 12, right: 12 }).alignItems(VerticalAlign.Center)

      Row() {
        Text(this.encoding)
          .fontSize(12).fontColor('#999999').backgroundColor('#F0F0F0')
          .borderRadius(4).padding({ left: 8, right: 8, top: 2, bottom: 2 })
        Blank()
        Text(`${this.lines.length} 行`).fontSize(12).fontColor('#999999')
      }
      .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else if (this.lines.length === 0) {
        Column() {
          Text('无法读取文件内容或文件为空').fontColor('#999999').fontSize(15)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        Stack() {
          List({ scroller: this.scroller }) {
            ForEach(this.lines.slice(0, this.displayCount), (line: string) => {
              ListItem() {
                Text((line && line.length > 0) ? line : '\u00A0')
                  .fontSize(15).fontColor($r('app.color.text_primary'))
                  .width('100%').lineHeight(22)
                  .padding({ left: 16, right: 40 })
              }
            })
            if (!this.getLoadedAll) {
              ListItem() {
                Button('加载更多').width('100%').fontSize(14)
                  .onClick(() => this.loadMore())
              }
            }
          }
          .width('100%').layoutWeight(1)
          .onScrollIndex((first: number) => {
            this.firstVisibleIndex = first;
          })

          Column() {
            Column()
              .width(4).height(this.getThumbHeight)
              .backgroundColor('#666666').borderRadius(2)
              .position({ y: this.getThumbOffset })
              .gesture(
                PanGesture({ direction: PanDirection.Vertical })
                  .onActionStart(() => { this.dragStartY = this.getThumbOffset; })
                  .onActionUpdate((event: GestureEvent) => {
                    const trackH: number = this.scrollbarTrackHeight;
                    const thumbH: number = this.getThumbHeight;
                    const y: number = Math.max(0, Math.min(trackH - thumbH, this.dragStartY + event.offsetY));
                    const ratio: number = (trackH - thumbH) > 0 ? y / (trackH - thumbH) : 0;
                    const remaining: number = this.lines.length - this.displayCount;
                    this.scroller.scrollToIndex(Math.max(0, Math.round(ratio * remaining)), false, ScrollAlign.START);
                  })
              )
          }
          .width(20).height('100%')
          .alignItems(HorizontalAlign.Center)
          .position({ right: 0 })
          .backgroundColor('#F5F5F5')
          .onClick((event: ClickEvent) => {
            if (this.lines.length <= this.displayCount) return;
            const ratio: number = event.y / this.scrollbarTrackHeight;
            const remaining: number = this.lines.length - this.displayCount;
            this.scroller.scrollToIndex(Math.max(0, Math.round(ratio * remaining)), true, ScrollAlign.START);
          })
        }
        .layoutWeight(1).width('100%')
        .onAreaChange((_: Area, newArea: Area) => {
          this.scrollbarTrackHeight = newArea.height as number;
        })
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.bg_page'))
  }
}
