import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanConfig } from '../model/ScanConfig';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct ScanConfigList {
  @State configs: ScanConfig[] = [];
  @State loading: boolean = true;

  async aboutToAppear(): Promise<void> {
    await this.load();
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
    const result = await promptAction.showDialog({
      title: '删除配置',
      message: `确认删除配置「${cfg.name}」？`,
      buttons: [{ text: '取消' }, { text: '删除' }]
    });
    if (result.index === 1) {
      await ScanConfigDao.delete(cfg.id);
      LogUtil.operation('删除配置', `配置ID=${cfg.id} 名称=${cfg.name}`);
      await this.load();
    }
  }

  private scanWith(cfg: ScanConfig): void {
    router.pushUrl({ url: 'pages/ScanProgress', params: { configId: cfg.id } }).catch((err: Error) => {
      LogUtil.e('ScanConfigList', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('扫描配置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
        Button('新增')
          .backgroundColor($r('app.color.primary'))
          .onClick(() => this.newConfig())
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

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
                  Text(`目录: ${cfg.folderName || '(未选择)'}   类型: ${cfg.fileTypes}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  Text(`递归: ${cfg.recursive ? '是' : '否'}   精确哈希: ${cfg.exactHash ? '是' : '否'}   最小: ${cfg.minSizeKb}KB`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  Button('删除')
                    .backgroundColor($r('app.color.danger'))
                    .height(32)
                    .alignSelf(FlexAlign.End)
                    .margin({ top: 6 })
                    .onClick(() => this.deleteConfig(cfg))
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(10)
              }
              .padding({ left: 12, right: 12, bottom: 10 })
            },
            (cfg: ScanConfig) => cfg.id.toString()
          )
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.bg_page'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
