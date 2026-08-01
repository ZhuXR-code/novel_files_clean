import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanConfig } from '../model/ScanConfig';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { LogUtil } from '../utils/LogUtil';
import { FormatUtil } from '../utils/FormatUtil';
import { TopBar } from '../components/TopBar';
import { ToastUtil } from '../utils/ToastUtil';

@Entry
@Component
struct ScanConfigList {
  @State configs: ScanConfig[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;

  // onPageShow 在每次页面显示时触发（含首次进入与从编辑页返回），
  // 相比仅在创建时触发一次的 aboutToAppear，可确保新增/编辑后的列表实时刷新
  onPageShow(): void {
    this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    try {
      this.configs = await ScanConfigDao.getAll();
    } catch (e) {
      LogUtil.e('ScanConfigList', `加载失败: ${(e as Error).message}`);
    }
    this.loading = false;
  }

  private editConfig(id: number): void {
    router.pushUrl({ url: 'pages/ConfigEdit', params: { configId: id } }).catch((err: Error) => {
      LogUtil.e('ScanConfigList', `跳转失败: ${err.message}`);
    });
  }

  private newConfig(): void {
    router.pushUrl({ url: 'pages/ConfigEdit' }).catch((err: Error) => {
      LogUtil.e('ScanConfigList', `跳转失败: ${err.message}`);
    });
  }

  private async deleteConfig(cfg: ScanConfig): Promise<void> {
    promptAction.showDialog({
      title: '删除配置',
      message: `确认删除配置「${cfg.name}」？`,
      buttons: [{ text: '取消', color: $r('app.color.text_secondary') }, { text: '删除', color: $r('app.color.danger') }]
    }).then(async (result) => {
      if (result.index === 1) {
        try {
          await ScanConfigDao.delete(cfg.id);
          LogUtil.operation('删除配置', `配置ID=${cfg.id} 名称=${cfg.name}`);
          await this.load();
        } catch (e) {
          LogUtil.e('ScanConfigList', `删除配置失败: ${(e as Error).message}`);
          ToastUtil.show('删除失败');
        }
      }
    });
  }

  private scanWith(cfg: ScanConfig): void {
    router.pushUrl({ url: 'pages/ScanProgress', params: { configId: cfg.id } }).catch((err: Error) => {
      LogUtil.e('ScanConfigList', `跳转失败: ${err.message}`);
    });
  }

  @Builder
  swipeDeleteConfig(cfg: ScanConfig) {
    Button('删除')
      .height('100%')
      .backgroundColor($r('app.color.danger'))
      .fontColor($r('app.color.text_on_primary'))
      .onClick(() => this.deleteConfig(cfg))
  }

  build() {
    Column() {
      TopBar({ title: '扫描配置', rightText: '新增', onRight: () => this.newConfig() })

      if (this.configs.length === 0) {
        Column() {
          Text('暂无配置')
            .fontSize(16)
            .fontColor($r('app.color.text_hint'))
          Text('点击右上角「新增」创建扫描配置')
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
        List() {
          ForEach(
            this.configs,
            (cfg: ScanConfig) => {
              ListItem() {
                Column({ space: 4 }) {
                  Row() {
                    Text(cfg.name || '未命名配置')
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    Button('编辑')
                      .height(32)
                      .onClick(() => this.editConfig(cfg.id))
                    Button('扫描')
                      .backgroundColor($r('app.color.primary'))
                      .height(32)
                      .margin({ left: 8 })
                      .onClick(() => this.scanWith(cfg))
                  }
                  .width('100%')
                  Text(`目录: ${FormatUtil.formatFolderDisplay(cfg.folderUri) || cfg.folderName || '(未选择)'}   类型: ${cfg.fileTypes}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  Text(`递归: ${cfg.recursive ? '是' : '否'}   精确哈希: ${cfg.exactHash ? '是' : '否'}   最小: ${cfg.minSizeKb}KB`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  Button('删除')
                    .backgroundColor($r('app.color.danger'))
                    .height(32)
                    .alignSelf(ItemAlign.End)
                    .margin({ top: 6 })
                    .onClick(() => this.deleteConfig(cfg))
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.bg_card'))
              .borderRadius(10)
            }
            .padding({ left: 12, right: 12, bottom: 10 })
            .swipeAction({ end: { builder: () => this.swipeDeleteConfig(cfg) } })
          },
          (cfg: ScanConfig) => cfg.id.toString()
        )
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor($r('app.color.bg_page'))
        }
        .onRefreshing(() => { this.load().finally(() => { this.refreshing = false; }); })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
