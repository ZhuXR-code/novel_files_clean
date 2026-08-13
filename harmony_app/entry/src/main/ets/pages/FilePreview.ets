import { router } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LogUtil } from '../utils/LogUtil';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { EncodingUtil } from '../utils/EncodingUtil';
import { TopBar } from '../components/TopBar';

// 对齐安卓端：流式分块读取，无文件大小上限
const READ_CHUNK_SIZE: number = 512 * 1024; // 每次读取 512KB
const MAX_LINE_CHARS: number = 4000; // 超长行强制切段（对齐安卓 MAX_LINE_CHARS）
const MAX_TOTAL_LINES: number = 200000; // 安全上限，防止 OOM
const CARRY_OVER: number = 4; // 跨块携带字节数（多字节字符边界安全）
const INITIAL_LINES: number = 200;
const LOAD_MORE_LINES: number = 200;
// G组 #27 全局字号偏好键（与 Settings.ets 保持一致）
const FONT_SCALE_KEY: string = 'settings_font_scale';

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
  @State scrollbarTrackWidth: number = 0;
  @State dragStartY: number = 0;
  @State dragStartX: number = 0;
  @State scrollbarActive: boolean = false;
  // 滚动条方向通过 AppStorage 全局共享，Settings 修改后立即响应（无需手动读取 Preferences）
  @StorageProp('previewScrollbarMode') scrollbarMode: string = 'vertical';
  @State fontSize: number = 15;
  // 字号调节面板折叠状态（对齐安卓 fontSizeExpanded：点击 Aa 图标切换显示/隐藏）
  @State fontPanelExpanded: boolean = true;
  @State truncated: boolean = false;
  @State previewError: string = '';
  // 对齐安卓端：预览范围（head=前50行快速预览, full=全部内容）
  @State previewMode: string = 'full';
  // 自动加载节流标志：避免滚动事件高频重复触发 loadMore
  @State loadingMore: boolean = false;

  private scroller: Scroller = new Scroller();
  private scrollbarTimer: number | null = null;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    // 防御异常跳转/deep link 导致 getParams() 返回 null 时访问属性崩溃。
    if (!params) {
      this.loading = false;
      this.previewError = '页面参数缺失';
      return;
    }
    this.fileName = (params['fileName'] as string) || '';
    this.filePath = (params['filePath'] as string) || '';
    // 对齐安卓端：读取预览范围参数（head=前50行, full=全部内容）
    if (params['previewMode'] !== undefined && params['previewMode'] !== null) {
      this.previewMode = params['previewMode'] as string;
    }
    // G组 #27 应用全局字号设置作为预览初始字号
    const fontScale: string = PreferencesUtil.getString(FONT_SCALE_KEY, 'standard');
    this.fontSize = fontScale === 'small' ? 13 : (fontScale === 'large' ? 18 : 15);
    await this.loadContent();
  }

  aboutToDisappear(): void {
    if (this.scrollbarTimer !== null) {
      clearTimeout(this.scrollbarTimer);
      this.scrollbarTimer = null;
    }
  }

  onPageShow(): void {
    // 重新读取字号设置（滚动条方向已通过 @StorageProp 自动响应，无需手动读取）
    const fontScale: string = PreferencesUtil.getString(FONT_SCALE_KEY, 'standard');
    this.fontSize = fontScale === 'small' ? 13 : (fontScale === 'large' ? 18 : 15);
  }

  /**
   * 流式分块读取文件内容（对齐安卓 PreviewLoader：无文件大小上限）。
   * 每次读取 READ_CHUNK_SIZE 字节，跨块携带 CARRY_OVER 字节保证多字节字符完整，
   * 超长行按 MAX_LINE_CHARS 切段，总行数上限 MAX_TOTAL_LINES 防 OOM。
   */
  async loadContent(): Promise<void> {
    if (!this.filePath) {
      this.loading = false;
      return;
    }
    try {
      const stat: fileIo.Stat = await fileIo.stat(this.filePath);
      const fileSize: number = stat.size;
      if (fileSize <= 0) {
        this.loading = false;
        return;
      }

      const file: fileIo.File = await fileIo.open(this.filePath, fileIo.OpenMode.READ_ONLY);
      try {
        const allLines: string[] = [];
        let leftoverLine: string = '';
        let leftoverBytes: Uint8Array = new Uint8Array(0);
        let encoding: string = 'utf-8';
        let bomSkip: number = 0;
        let encodingDetected: boolean = false;
        let fileOffset: number = 0;

        while (fileOffset < fileSize || leftoverBytes.length > 0) {
          let chunkBytes: Uint8Array;
          if (fileOffset < fileSize) {
            const readSize: number = Math.min(READ_CHUNK_SIZE, fileSize - fileOffset);
            const chunkBuf: ArrayBuffer = new ArrayBuffer(readSize);
            const read: number = await fileIo.read(file.fd, chunkBuf, { offset: fileOffset, length: readSize });
            chunkBytes = new Uint8Array(chunkBuf.slice(0, read));
            fileOffset += read;
          } else {
            chunkBytes = new Uint8Array(0);
          }

          const combined: Uint8Array = this.concatBytes(leftoverBytes, chunkBytes);
          const isLast: boolean = fileOffset >= fileSize;

          // 首个非空块检测编码（关键修复：用 EncodingUtil.decodeStrict 统一评分对齐 iOS/安卓）
          if (!encodingDetected && combined.length > 0) {
            if (combined.length >= 3 && combined[0] === 0xEF && combined[1] === 0xBB && combined[2] === 0xBF) {
              encoding = 'utf-8';
              bomSkip = 3;
              this.encoding = 'UTF-8\u2009BOM';
            } else {
              // decodeStrict 内部做 CJK 占比评分 + 异常字符惩罚，
              // 纠正「GBK 文件被误判为合法 UTF-8 → 解码成乱码（损坏文件）」，
              // 并以 GB18030 兜底（GBK 超集），失败回退 GBK。
              const encName: string = EncodingUtil.decodeStrict(combined);
              if (encName === 'GB18030') {
                encoding = 'gb18030';
                this.encoding = 'GB18030';
              } else if (encName === 'GBK') {
                encoding = 'gbk';
                this.encoding = 'GBK';
              } else {
                encoding = 'utf-8';
                this.encoding = 'UTF-8';
              }
            }
            encodingDetected = true;
          }

          // 保留末尾 CARRY_OVER 字节到下一块（多字节字符边界安全）
          let safeBytes: Uint8Array;
          if (isLast) {
            safeBytes = combined;
            leftoverBytes = new Uint8Array(0);
          } else {
            const safeLength: number = Math.max(0, combined.length - CARRY_OVER);
            safeBytes = combined.slice(0, safeLength);
            leftoverBytes = combined.slice(safeLength);
          }

          // 跳过 BOM
          if (bomSkip > 0 && safeBytes.length >= bomSkip) {
            safeBytes = safeBytes.slice(bomSkip);
            bomSkip = 0;
          }

          if (safeBytes.length > 0) {
            const text: string = this.decodeBytes(safeBytes, encoding);
            const fullText: string = leftoverLine + text;
            const textLines: string[] = fullText.split('\n');
            // 末行可能不完整（块边界截断），留到下一块拼接
            leftoverLine = textLines.pop() || '';

            for (const line of textLines) {
              this.addSplitLine(allLines, line.replace(/\r$/, ''));
              if (allLines.length >= MAX_TOTAL_LINES) break;
            }
          }

          // head 模式：读到 50 行即停
          if (this.previewMode === 'head' && allLines.length >= 50) break;
          if (allLines.length >= MAX_TOTAL_LINES) break;
          if (isLast) break;
        }

        // 处理最后残留的不完整行
        if (leftoverLine.length > 0 && allLines.length < MAX_TOTAL_LINES) {
          this.addSplitLine(allLines, leftoverLine.replace(/\r$/, ''));
        }

        this.truncated = allLines.length >= MAX_TOTAL_LINES;
        this.lines = allLines;

        if (this.previewMode === 'head') {
          // 前 50 行快速预览
          this.lines = this.lines.slice(0, 50);
          this.displayCount = this.lines.length;
        } else if (this.previewMode === 'tail') {
          // 后 100 行预览：只保留文件末尾 100 行
          if (this.lines.length > 100) {
            this.lines = this.lines.slice(this.lines.length - 100);
          }
          this.displayCount = this.lines.length;
        } else {
          this.displayCount = Math.min(this.lines.length, INITIAL_LINES);
        }
      } finally {
        await fileIo.close(file);
      }
    } catch (e) {
      LogUtil.e('FilePreview', `读取失败: ${(e as Error).message}`);
      this.previewError = `预览失败: ${(e as Error).message}`;
    }
    this.loading = false;
  }

  /** 超长行按 MAX_LINE_CHARS 切段（对齐安卓 MAX_LINE_CHARS）。 */
  private addSplitLine(lines: string[], text: string): void {
    if (text.length <= MAX_LINE_CHARS) {
      lines.push(text);
    } else {
      for (let i = 0; i < text.length; i += MAX_LINE_CHARS) {
        lines.push(text.substring(i, Math.min(i + MAX_LINE_CHARS, text.length)));
      }
    }
  }

  /** 拼接两个 Uint8Array。 */
  private concatBytes(a: Uint8Array, b: Uint8Array): Uint8Array {
    if (a.length === 0) return b;
    if (b.length === 0) return a;
    const result: Uint8Array = new Uint8Array(a.length + b.length);
    result.set(a, 0);
    result.set(b, a.length);
    return result;
  }

  private decodeBytes(bytes: Uint8Array, enc: string): string {
    try {
      const decoder: util.TextDecoder = new util.TextDecoder(enc);
      return decoder.decodeToString(bytes);
    } catch {
      return '';
    }
  }

  // 对齐 iOS/安卓：采样尾部被截断的不完整多字节序列视为合法前缀（避免采样边界误判）
  private isValidUtf8(bytes: Uint8Array): boolean {
    let i: number = 0;
    const len: number = bytes.length;
    while (i < len) {
      const b: number = bytes[i];
      if (b <= 0x7F) {
        i++;
      } else if (b >= 0xC2 && b <= 0xDF) {
        if (i + 1 >= len) return true;
        if ((bytes[i + 1] & 0xC0) !== 0x80) return false;
        i += 2;
      } else if (b === 0xE0) {
        if (i + 2 >= len) return true;
        if (bytes[i + 1] < 0xA0 || bytes[i + 1] > 0xBF ||
          (bytes[i + 2] & 0xC0) !== 0x80) return false;
        i += 3;
      } else if (b >= 0xE1 && b <= 0xEF) {
        if (i + 2 >= len) return true;
        if ((bytes[i + 1] & 0xC0) !== 0x80 ||
          (bytes[i + 2] & 0xC0) !== 0x80) return false;
        i += 3;
      } else if (b === 0xF0) {
        if (i + 3 >= len) return true;
        if (bytes[i + 1] < 0x90 || bytes[i + 1] > 0xBF ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else if (b >= 0xF1 && b <= 0xF3) {
        if (i + 3 >= len) return true;
        if ((bytes[i + 1] & 0xC0) !== 0x80 ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else if (b >= 0xF4 && b <= 0xF7) {
        if (i + 3 >= len) return true;
        if (bytes[i + 1] < 0x80 || bytes[i + 1] > 0x8F ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else {
        return false;
      }
    }
    return true;
  }

  private loadMore(): void {
    // head / tail 模式下不自动加载更多（head=前50行，tail=后100行，均为固定范围）
    if (this.previewMode === 'head' || this.previewMode === 'tail') return;
    if (this.getLoadedAll) return;
    if (this.loadingMore) return;
    this.loadingMore = true;
    const prev: number = this.displayCount;
    this.displayCount = Math.min(this.displayCount + LOAD_MORE_LINES, this.lines.length);
    // 加载是纯本地状态追加，无需异步等待；轻量 setTimeout 释放节流锁，
    // 避免惯性滚动期间 onScrollIndex 高频重入导致一屏内多次跳增。
    setTimeout(() => {
      this.loadingMore = false;
      // 若本次追加后仍未到底且用户已接近新末尾，继续预加载（惯性滑动兜底）
      if (!this.getLoadedAll && prev + this.estimatedVisibleRows() + 20 >= this.displayCount) {
        this.loadMore();
      }
    }, 0);
  }

  /** 估算当前一屏可见行数（基于字体大小+行高），用于积极的滚动预加载阈值。 */
  private estimatedVisibleRows(): number {
    const lineHeight: number = this.fontSize + 7;
    if (lineHeight <= 0 || this.scrollbarTrackHeight <= 0) return 20;
    return Math.max(5, Math.ceil(this.scrollbarTrackHeight / lineHeight));
  }

  private decFont(): void {
    if (this.fontSize > 10) {
      this.fontSize -= 1;
    }
  }

  private incFont(): void {
    if (this.fontSize < 28) {
      this.fontSize += 1;
    }
  }

  private activateScrollbar(): void {
    if (this.scrollbarTimer !== null) {
      clearTimeout(this.scrollbarTimer);
      this.scrollbarTimer = null;
    }
    this.scrollbarActive = true;
  }

  private deactivateScrollbar(): void {
    if (this.scrollbarTimer !== null) {
      clearTimeout(this.scrollbarTimer);
    }
    this.scrollbarTimer = setTimeout(() => {
      this.scrollbarActive = false;
      this.scrollbarTimer = null;
    }, 500);
  }

  private scrollToRatio(ratio: number, animated: boolean = true): void {
    if (this.lines.length <= this.displayCount) return;
    const remaining: number = this.lines.length - this.displayCount;
    const target: number = Math.max(0, Math.min(remaining, Math.round(ratio * remaining)));
    this.scroller.scrollToIndex(target, animated, ScrollAlign.START);
  }

  get getLoadedAll(): boolean {
    // head / tail 模式视为已加载完毕，阻止自动加载更多
    if (this.previewMode === 'head' || this.previewMode === 'tail') return true;
    return this.displayCount >= this.lines.length;
  }

  // 对齐安卓 scrollbarVisible：仅当内容超出已加载范围时才显示滚动条
  get getScrollbarVisible(): boolean {
    return this.lines.length > this.displayCount;
  }

  get getThumbHeight(): number {
    const trackH: number = this.scrollbarTrackHeight;
    if (trackH <= 0 || this.lines.length <= 0) return 48;
    const ratio: number = this.displayCount / this.lines.length;
    return Math.max(trackH * ratio, 48);
  }

  get getThumbOffset(): number {
    const trackH: number = this.scrollbarTrackHeight;
    const thumbH: number = this.getThumbHeight;
    const remaining: number = this.lines.length - this.displayCount;
    if (trackH <= 0 || remaining <= 0 || this.displayCount <= 0) return 0;
    const ratio: number = this.firstVisibleIndex / remaining;
    return Math.max(0, Math.min(ratio * (trackH - thumbH), trackH - thumbH));
  }

  get getThumbWidth(): number {
    const trackW: number = this.scrollbarTrackWidth;
    if (trackW <= 0 || this.lines.length <= 0) return 48;
    const ratio: number = this.displayCount / this.lines.length;
    return Math.max(trackW * ratio, 48);
  }

  get getThumbOffsetHorizontal(): number {
    const trackW: number = this.scrollbarTrackWidth;
    const thumbW: number = this.getThumbWidth;
    const remaining: number = this.lines.length - this.displayCount;
    if (trackW <= 0 || remaining <= 0 || this.displayCount <= 0) return 0;
    const ratio: number = this.firstVisibleIndex / remaining;
    return Math.max(0, Math.min(ratio * (trackW - thumbW), trackW - thumbW));
  }

  build() {
    Column() {
      TopBar({ title: this.fileName })

      Row() {
        Text(this.encoding)
          .fontSize(12).fontColor($r('app.color.text_hint')).backgroundColor($r('app.color.scrollbar_track'))
          .borderRadius(4).padding({ left: 8, right: 8, top: 2, bottom: 2 })
        if (this.truncated) {
          Text(`文件过大，仅预览前 ${MAX_TOTAL_LINES} 行`)
            .fontSize(11).fontColor($r('app.color.warning'))
            .margin({ left: 8 })
        }
        Blank()
        // Aa 图标按钮：折叠/展开字号调节面板（对齐安卓 fontSizeExpanded）
        Text('Aa')
          .fontSize(14).fontColor($r('app.color.text_secondary'))
          .margin({ right: 8 })
          .onClick(() => this.fontPanelExpanded = !this.fontPanelExpanded)
        if (this.fontPanelExpanded) {
          Button('A-')
            .fontSize(12).height(28).backgroundColor($r('app.color.bg_card')).fontColor($r('app.color.text_primary'))
            .onClick(() => this.decFont())
          Text(`${this.fontSize}`)
            .fontSize(12).fontColor($r('app.color.text_secondary'))
            .margin({ left: 4, right: 4 })
          Button('A+')
            .fontSize(12).height(28).backgroundColor($r('app.color.bg_card')).fontColor($r('app.color.text_primary'))
            .onClick(() => this.incFont())
        }
        Text(`${this.lines.length} 行`)
          .fontSize(12).fontColor($r('app.color.text_hint'))
          .margin({ left: 8 })
      }
      .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else if (this.previewError.length > 0) {
        // 对齐安卓：专门错误显示（红色提示）
        Column() {
          Text(this.previewError).fontColor($r('app.color.warning')).fontSize(15)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else if (this.lines.length === 0) {
        Column() {
          Text('无法读取文件内容或文件为空').fontColor($r('app.color.text_hint')).fontSize(15)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        if (this.scrollbarMode === 'vertical') {
          this.verticalReader()
        } else {
          this.horizontalReader()
        }
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.bg_page')).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  lineListItem(line: string, index: number) {
    ListItem() {
      Row() {
        Text(`${index + 1}`)
          .fontSize(this.fontSize - 2)
          .fontColor($r('app.color.text_hint'))
          .width(44)
          .textAlign(TextAlign.End)
        Text((line && line.length > 0) ? line : '\u00A0')
          .fontSize(this.fontSize).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).lineHeight(this.fontSize + 7)
          .padding({ left: 8, right: this.scrollbarMode === 'vertical' ? 40 : 16 })
      }
      .width('100%')
    }
  }

  @Builder
  loadMoreItem() {
    ListItem() {
      if (this.previewMode === 'head') {
        Text('— 仅预览前50行，返回选择「全部内容」可查看完整 —')
          .width('100%').textAlign(TextAlign.Center)
          .fontSize(12).fontColor($r('app.color.text_hint')).padding(12)
      } else if (this.previewMode === 'tail') {
        Text('— 仅预览后100行，返回选择「全部内容」可查看完整 —')
          .width('100%').textAlign(TextAlign.Center)
          .fontSize(12).fontColor($r('app.color.text_hint')).padding(12)
      } else if (this.getLoadedAll) {
        Text('— 已到末尾 —')
          .width('100%').textAlign(TextAlign.Center)
          .fontSize(12).fontColor($r('app.color.text_hint')).padding(12)
      } else {
        // 自动加载模式：不再暴露「加载更多」按钮，滚动到底部自动追加
        // （onScrollIndex 触发 loadMore），此处仅展示加载状态提示
        Row() {
          LoadingProgress().width(16).height(16)
          Text('正在加载更多…').fontSize(12).fontColor($r('app.color.text_hint'))
            .margin({ left: 8 })
        }
        .width('100%').justifyContent(FlexAlign.Center).padding(12)
      }
    }
  }

  @Builder
  verticalReader() {
    Stack() {
      List({ scroller: this.scroller }) {
        ForEach(this.lines.slice(0, this.displayCount), (line: string, index: number) => {
          this.lineListItem(line, index)
        })
        this.loadMoreItem()
      }
      .width('100%').layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .onScrollIndex((first: number) => {
        this.firstVisibleIndex = first;
        // 接近末尾即自动预加载：末可见项 + 一屏缓冲接近已加载末尾时触发，
        // 不等用户真正滑到底才加载（解决"划到最下面才加载"的体感问题）
        if (!this.getLoadedAll && this.displayCount - (first + this.estimatedVisibleRows()) <= 10) {
          this.loadMore();
        }
      })

      // 仅在内容溢出时显示滚动条（对齐安卓 scrollbarVisible）
      if (this.getScrollbarVisible) {
        // 全高触摸轨道（比可见滑块宽，方便点到）；点按/拖拽均触发变宽并跳转
        Column() {
          // 可见滑块（纯展示，手势由外层轨道统一处理，对齐安卓 thumb 仅展示）
          Column()
            .width(this.scrollbarActive ? 12 : 4)
            .height(this.getThumbHeight)
            .backgroundColor($r('app.color.btn_primary_bg'))
            .opacity(0.55)
            .borderRadius(this.scrollbarActive ? 6 : 2)
            .offset({ y: this.getThumbOffset })
            .animation({ duration: 150, curve: Curve.EaseInOut })
        }
        .width(20).height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
        .position({ right: 0 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.activateScrollbar();
            // 首次触摸即跳转到对应位置（对齐安卓 awaitFirstDown 跳转）
            if (this.scrollbarTrackHeight > 0) {
              this.scrollToRatio(event.touches[0].y / this.scrollbarTrackHeight, true);
            }
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.deactivateScrollbar();
          }
        })
        .gesture(
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart(() => { this.dragStartY = this.getThumbOffset; })
            .onActionUpdate((event: GestureEvent) => {
              const trackH: number = this.scrollbarTrackHeight;
              const thumbH: number = this.getThumbHeight;
              const y: number = Math.max(0, Math.min(trackH - thumbH, this.dragStartY + event.offsetY));
              const ratio: number = (trackH - thumbH) > 0 ? y / (trackH - thumbH) : 0;
              this.scrollToRatio(ratio, false);
            })
            .onActionEnd(() => this.deactivateScrollbar())
        )
      }
    }
    .layoutWeight(1).width('100%')
    .onAreaChange((_: Area, newArea: Area) => {
      this.scrollbarTrackHeight = newArea.height as number;
    })
  }

  @Builder
  horizontalReader() {
    Column() {
      // 仅在内容溢出时显示滚动条（对齐安卓 scrollbarVisible）
      if (this.getScrollbarVisible) {
        Row() {
          // 可见滑块（纯展示，手势由外层轨道统一处理，对齐安卓 thumb 仅展示）
          Row()
            .width(this.getThumbWidth)
            .height(this.scrollbarActive ? 12 : 4)
            .backgroundColor($r('app.color.btn_primary_bg'))
            .opacity(0.55)
            .borderRadius(this.scrollbarActive ? 6 : 2)
            .offset({ x: this.getThumbOffsetHorizontal })
            .animation({ duration: 150, curve: Curve.EaseInOut })
        }
        .width('100%').height(20)
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.scrollbar_track'))
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.activateScrollbar();
            // 首次触摸即跳转到对应位置（对齐安卓 awaitFirstDown 跳转）
            if (this.scrollbarTrackWidth > 0) {
              this.scrollToRatio(event.touches[0].x / this.scrollbarTrackWidth, true);
            }
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.deactivateScrollbar();
          }
        })
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionStart(() => { this.dragStartX = this.getThumbOffsetHorizontal; })
            .onActionUpdate((event: GestureEvent) => {
              const trackW: number = this.scrollbarTrackWidth;
              const thumbW: number = this.getThumbWidth;
              const x: number = Math.max(0, Math.min(trackW - thumbW, this.dragStartX + event.offsetX));
              const ratio: number = (trackW - thumbW) > 0 ? x / (trackW - thumbW) : 0;
              this.scrollToRatio(ratio, false);
            })
            .onActionEnd(() => this.deactivateScrollbar())
        )
        .onAreaChange((_: Area, newArea: Area) => {
          this.scrollbarTrackWidth = newArea.width as number;
        })
      }

      List({ scroller: this.scroller }) {
        ForEach(this.lines.slice(0, this.displayCount), (line: string, index: number) => {
          this.lineListItem(line, index)
        })
        this.loadMoreItem()
      }
      .width('100%').layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .onScrollIndex((first: number) => {
        this.firstVisibleIndex = first;
        // 接近末尾即自动预加载：末可见项 + 一屏缓冲接近已加载末尾时触发，
        // 不等用户真正滑到底才加载（解决"划到最下面才加载"的体感问题）
        if (!this.getLoadedAll && this.displayCount - (first + this.estimatedVisibleRows()) <= 10) {
          this.loadMore();
        }
      })
    }
    .width('100%').layoutWeight(1)
  }
}
