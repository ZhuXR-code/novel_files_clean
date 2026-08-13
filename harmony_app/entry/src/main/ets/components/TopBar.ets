import { router } from '@kit.ArkUI';

/**
 * 统一极简顶栏：左返回箭头 + 居中标题 + 右侧文字操作。
 * 用于替换各页面手写的 Row{Button('返回')...} 顶栏。
 * 底部发丝级分割线，无阴影，符合 Minimalism 风格。
 */
@Component
export struct TopBar {
  @Prop title: string = '';
  @Prop showBack: boolean = true;
  @Prop rightText: string = '';
  onBack: () => void = () => router.back();
  onRight: () => void = () => {};
  // 挖孔区避让：页面普遍 expandSafeArea 到状态栏下方，顶栏需额外预留状态栏高度，
  // 避免返回箭头/标题被摄像头挖孔遮挡（上架 UX 检测项）
  @StorageProp('statusBarHeightPx') statusBarHeightPx: number = 0;

  build() {
    Row() {
      if (this.showBack) {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => this.onBack())
      } else {
        Row().width(28)
      }

      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.rightText.length > 0) {
        Text(this.rightText)
          .fontSize(15)
          .fontColor($r('app.color.primary'))
          .onClick(() => this.onRight())
      } else {
        Row().width(28)
      }
    }
    .width('100%')
    .height(52 + px2vp(this.statusBarHeightPx))
    .padding({ left: 12, right: 12, top: px2vp(this.statusBarHeightPx) })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: { bottom: 0.5 }, color: $r('app.color.divider') })
  }
}
