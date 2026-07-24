import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanConfig } from '../model/ScanConfig';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { AppContext } from '../utils/AppContext';
import { ScanService } from '../service/ScanService';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct ConfigEdit {
  @State configId: number = 0;
  @State name: string = '';
  @State folderUri: string = '';
  @State folderName: string = '';
  @State fileTypes: string = 'txt';
  @State minSizeKb: string = '0';
  @State recursive: boolean = true;
  @State exactHash: boolean = false;
  @State excludedFolders: string = '';
  @State saving: boolean = false;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['configId'] !== undefined && params['configId'] !== null) {
      this.configId = params['configId'] as number;
      const cfg = await ScanConfigDao.getById(this.configId);
      if (cfg) {
        this.name = cfg.name;
        this.folderUri = cfg.folderUri;
        this.folderName = cfg.folderName;
        this.fileTypes = cfg.fileTypes;
        this.minSizeKb = cfg.minSizeKb.toString();
        this.recursive = cfg.recursive;
        this.exactHash = cfg.exactHash;
        this.excludedFolders = cfg.excludedFolders;
      }
    }
  }

  private async selectDir(): Promise<void> {
    const ctx = AppContext.get();
    if (!ctx) {
      return;
    }
    try {
      const uri = await ScanService.selectDirectory(ctx);
      this.folderUri = uri;
      this.folderName = uri.substring(uri.lastIndexOf('/') + 1);
    } catch (e) {
      LogUtil.e('ConfigEdit', `选择目录失败: ${(e as Error).message}`);
    }
  }

  private async save(): Promise<void> {
    if (this.folderUri.length === 0) {
      promptAction.showToast({ message: '请先选择扫描目录' });
      return;
    }
    this.saving = true;
    if (this.name.trim().length === 0) {
      this.name = this.folderName || '配置';
    }
    const cfg: ScanConfig = new ScanConfig();
    cfg.id = this.configId;
    cfg.name = this.name.trim();
    cfg.folderUri = this.folderUri;
    cfg.folderName = this.folderName;
    cfg.fileTypes = this.fileTypes.trim().length === 0 ? 'txt' : this.fileTypes.trim();
    cfg.minSizeKb = Number(this.minSizeKb) || 0;
    cfg.recursive = this.recursive;
    cfg.exactHash = this.exactHash;
    cfg.excludedFolders = this.excludedFolders.trim();
    if (this.configId > 0) {
      await ScanConfigDao.update(cfg);
      LogUtil.operation('更新配置', `配置ID=${cfg.id} 名称=${cfg.name}`);
    } else {
      const id = await ScanConfigDao.insert(cfg);
      this.configId = id;
      LogUtil.operation('创建配置', `配置ID=${id} 名称=${cfg.name}`);
    }
    this.saving = false;
    router.back();
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text(this.configId > 0 ? '编辑配置' : '新增配置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
        Button('保存')
          .backgroundColor($r('app.color.primary'))
          .enabled(!this.saving)
          .onClick(() => this.save())
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          // 配置名称
          Column({ space: 6 }) {
            Text('配置名称').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            TextInput({ text: this.name, placeholder: '请输入配置名称' })
              .onChange((v: string) => (this.name = v))
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 扫描目录
          Column({ space: 6 }) {
            Text('扫描目录').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            Row() {
              Text(this.folderName || '(未选择)')
                .fontSize(14)
                .fontColor(this.folderName ? $r('app.color.text_primary') : $r('app.color.text_hint'))
                .layoutWeight(1)
              Button('选择目录')
                .backgroundColor($r('app.color.primary'))
                .height(36)
                .onClick(() => this.selectDir())
            }
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 文件类型
          Column({ space: 6 }) {
            Text('文件类型(逗号分隔)').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            TextInput({ text: this.fileTypes, placeholder: 'txt' })
              .onChange((v: string) => (this.fileTypes = v))
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 最小体积
          Column({ space: 6 }) {
            Text('最小体积(KB, 0=不限)').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            TextInput({ text: this.minSizeKb, placeholder: '0' })
              .type(InputType.Number)
              .onChange((v: string) => (this.minSizeKb = v))
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 递归子目录
          Column({ space: 6 }) {
            Text('递归子目录').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.recursive }).onChange((v: boolean) => (this.recursive = v))
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 精确哈希比对
          Column({ space: 6 }) {
            Text('精确哈希比对(较慢)').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.exactHash }).onChange((v: boolean) => (this.exactHash = v))
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 排除文件夹
          Column({ space: 6 }) {
            Text('排除文件夹(分号分隔)').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            TextInput({ text: this.excludedFolders, placeholder: '如 已读;缓存' })
              .onChange((v: string) => (this.excludedFolders = v))
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
