import { router } from '@kit.ArkUI';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { PermissionRequester } from '../utils/PermissionRequester';
import { LogUtil } from '../utils/LogUtil';
import { HomePage } from './Index';
import { LibraryTab } from './LibraryList';
import { MinePage } from './Settings';

/**
 * 应用主壳：底部 3 标签导航（首页 / 文库 / 我的）。
 * 合集内容与文库一致，故合并到文库入口。
 * 二级页通过 router.pushUrl 推入，全屏覆盖本主壳（TabBar 自然隐藏），
 * 系统返回键 pop 后回到对应 Tab。
 */
@Entry
@Component
struct MainTabs {
  @State currentIndex: number = 0;
  @StorageProp('fontScale') fontScaleNum: number = 1.0;

  async aboutToAppear(): Promise<void> {
    // 首次启动隐私协议拦截（原 Index.ets 逻辑上移）
    if (!PreferencesUtil.getBoolean('privacy_agreed', false)) {
      router.replaceUrl({ url: 'pages/PrivacyPolicy', params: { mode: 'agree' } });
      return;
    }
    // 已同意隐私政策：此时再申请 user_grant 文件目录权限（合规要求：同意前不得申请）。
    // 入口内部已做去重与防重入，不会每次进首页都弹窗。
    PermissionRequester.requestAfterPrivacyAgreed().catch((e: Error) => {
      LogUtil.w('MainTabs', `隐私同意后申请权限异常: ${e.message}`);
    });
  }

  @Builder
  tabBuilder(title: string, icon: Resource, index: number) {
    Column({ space: 3 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.currentIndex === index ? $r('app.color.primary') : $r('app.color.text_hint'))
      Text(title)
        .fontSize(Math.round(11 * this.fontScaleNum))
        .fontColor(this.currentIndex === index ? $r('app.color.primary') : $r('app.color.text_hint'))
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
        TabContent() {
          HomePage()
        }
          .tabBar(this.tabBuilder('首页', $r('app.media.tab_home'), 0))

        TabContent() {
          LibraryTab()
        }
          .tabBar(this.tabBuilder('文库', $r('app.media.tab_library'), 1))

        TabContent() {
          MinePage()
        }
          .tabBar(this.tabBuilder('我的', $r('app.media.tab_mine'), 2))
      }
      .barHeight(56)
      .barMode(BarMode.Fixed)
      .scrollable(true)
      .onChange((i: number) => {
        this.currentIndex = i;
        // 切到首页/文库时推送刷新信号，触发列表重载（TabContent 子组件不触发 onPageShow）
        if (i === 0 || i === 1) {
          AppStorage.setOrCreate('libraryRefreshTick', Date.now());
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
