import { router } from '@kit.ArkUI';
import { ScanConfig } from '../model/ScanConfig';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { AppContext } from '../utils/AppContext';
import { ScanService } from '../service/ScanService';
import { LogUtil } from '../utils/LogUtil';
import { FormatUtil } from '../utils/FormatUtil';
import { TopBar } from '../components/TopBar';
import { AppTextInput } from '../components/AppTextInput';
import { ToastUtil } from '../utils/ToastUtil';

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
  @State excludedTitles: string = '';          // 排除的原始书名，逗号/换行分隔
  @State excludedTitleKeywords: string = '';    // 排除的书名词汇，逗号/换行分隔
  @State saving: boolean = false;
  // D组 #11 扫描模式：quick=快速(不计算哈希) / deep=精确(计算哈希)
  @State scanMode: string = 'quick';
  // D组 #10 常用文件类型快捷勾选
  private readonly commonTypes: string[] = ['txt', 'epub', 'mobi', 'pdf', 'doc', 'docx', 'azw3', 'fb2'];

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
        this.excludedTitles = cfg.excludedTitles;
        this.excludedTitleKeywords = cfg.excludedTitleKeywords;
        this.scanMode = cfg.exactHash ? 'deep' : 'quick';
      }
    } else {
      // D组 #13 新建配置预填全局默认值
      this.fileTypes = 'txt';
      this.minSizeKb = '0';
      this.recursive = true;
      this.exactHash = false;
      this.scanMode = 'quick';
    }
  }

  // D组 #10 切换文件类型勾选
  private toggleFileType(type: string): void {
    const current: string[] = this.fileTypes.split(/[;；,，\s]+/).filter((s) => s.length > 0);
    const idx: number = current.indexOf(type);
    if (idx >= 0) {
      current.splice(idx, 1);
    } else {
      current.push(type);
    }
    this.fileTypes = current.join(',');
  }

  private isTypeChecked(type: string): boolean {
    const current: string[] = this.fileTypes.split(/[;；,，\s]+/).filter((s) => s.length > 0);
    return current.includes(type);
  }

  // D组 #11 扫描模式切换
  private setScanMode(mode: string): void {
    this.scanMode = mode;
    this.exactHash = mode === 'deep';
  }

  // D组 #12 解析当前已选排除文件夹列表
  private getExcludedList(): string[] {
    return this.excludedFolders
      .split(/[;；,，]/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
  }

  // D组 #12 选择要排除的文件夹（从文件系统选择，取末级目录名作为排除名）
  private async selectExcludeFolder(): Promise<void> {
    const ctx = AppContext.get();
    if (!ctx) {
      return;
    }
    try {
      const uri = await ScanService.selectDirectory(ctx, this.folderUri);
      if (uri.length === 0) {
        return; // 用户取消
      }
      const folderName: string = FormatUtil.formatFolderDisplay(uri);
      if (folderName.length === 0) {
        ToastUtil.show('无法解析文件夹名称');
        return;
      }
      const list: string[] = this.getExcludedList();
      if (list.includes(folderName)) {
        ToastUtil.show('该文件夹已在排除列表');
        return;
      }
      list.push(folderName);
      this.excludedFolders = list.join(';');
      ToastUtil.show(`已添加排除: ${folderName}`);
    } catch (e) {
      LogUtil.e('ConfigEdit', `选择排除文件夹失败: ${(e as Error).message}`);
      ToastUtil.show('选择失败，请重试');
    }
  }

  // D组 #12 移除某个排除文件夹
  private removeExcludeFolder(folder: string): void {
    const list: string[] = this.getExcludedList().filter((s) => s !== folder);
    this.excludedFolders = list.join(';');
  }

  private async selectDir(): Promise<void> {
    const ctx = AppContext.get();
    if (!ctx) {
      return;
    }
    try {
      const uri = await ScanService.selectDirectory(ctx, this.folderUri);
      if (uri.length === 0) {
        return; // 用户取消选择
      }
      this.folderUri = uri;
      this.folderName = FormatUtil.formatFolderDisplay(uri);
    } catch (e) {
      LogUtil.e('ConfigEdit', `选择目录失败: ${(e as Error).message}`);
      ToastUtil.show(`选择失败: ${(e as Error).message}`);
    }
  }

  private async save(): Promise<void> {
    if (this.folderUri.length === 0) {
      ToastUtil.show('请先选择扫描目录');
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
    cfg.excludedTitles = this.excludedTitles.trim();
    cfg.excludedTitleKeywords = this.excludedTitleKeywords.trim();
    try {
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
    } catch (e) {
      LogUtil.e('ConfigEdit', `保存配置失败: ${(e as Error).message}`);
      ToastUtil.show(`保存失败: ${(e as Error).message}`);
      this.saving = false;
    }
  }

  onBackPress(): boolean {
    if (this.saving) {
      ToastUtil.show('正在保存，请稍候');
      return true;
    }
    return false;
  }

  build() {
    Column() {
      TopBar({
        title: this.configId > 0 ? '编辑配置' : '新增配置',
        rightText: this.saving ? '保存中…' : '保存',
        onRight: () => { if (!this.saving) this.save(); }
      })

      Scroll() {
        Column({ space: 16 }) {
          // 配置名称
          Column({ space: 6 }) {
            Text('配置名称').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            AppTextInput({ text: this.name, placeholder: '请输入配置名称', onChangeCallback: (v: string) => (this.name = v) })
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
            AppTextInput({ text: this.fileTypes, placeholder: 'txt', onChangeCallback: (v: string) => (this.fileTypes = v) })
            // D组 #10 常用文件类型快捷勾选
            Text('快捷勾选:').fontSize(12).fontColor($r('app.color.text_hint'))
              .margin({ top: 6 }).alignSelf(ItemAlign.Start)
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
              ForEach(
                this.commonTypes,
                (t: string) => {
                  Button(t)
                    .fontSize(11)
                    .height(28)
                    .margin({ right: 6, bottom: 6 })
                    .backgroundColor(this.isTypeChecked(t) ? $r('app.color.primary') : $r('app.color.bg_page'))
                    .fontColor(this.isTypeChecked(t) ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
                    .onClick(() => this.toggleFileType(t))
                },
                (t: string) => t
              )
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // D组 #11 扫描模式
          Column({ space: 6 }) {
            Text('扫描模式').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            Row({ space: 8 }) {
              Button('快速扫描')
                .fontSize(12)
                .height(34)
                .layoutWeight(1)
                .backgroundColor(this.scanMode === 'quick' ? $r('app.color.primary') : $r('app.color.bg_page'))
                .fontColor(this.scanMode === 'quick' ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
                .onClick(() => this.setScanMode('quick'))
              Button('精确扫描')
                .fontSize(12)
                .height(34)
                .layoutWeight(1)
                .backgroundColor(this.scanMode === 'deep' ? $r('app.color.primary') : $r('app.color.bg_page'))
                .fontColor(this.scanMode === 'deep' ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
                .onClick(() => this.setScanMode('deep'))
            }
            .width('100%')
            Text(this.scanMode === 'quick' ? '快速模式：按文件名规则解析，不计算内容哈希，速度快' : '精确模式：计算内容 MD5 哈希，可检测内容完全相同的文件，较慢')
              .fontSize(11)
              .fontColor($r('app.color.text_hint'))
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 最小体积
          Column({ space: 6 }) {
            Text('最小体积(KB, 0=不限)').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            AppTextInput({ text: this.minSizeKb, placeholder: '0', inputType: InputType.Number, onChangeCallback: (v: string) => (this.minSizeKb = v) })
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

          // 排除文件夹
          Column({ space: 6 }) {
            Text('排除文件夹(分号分隔)').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            Row() {
              AppTextInput({ text: this.excludedFolders, placeholder: '如 已读;缓存', expand: true, onChangeCallback: (v: string) => (this.excludedFolders = v) })
              // D组 #12 选择按钮：从文件系统选择要排除的文件夹
              Button('选择')
                .fontSize(12)
                .height(40)
                .margin({ left: 8 })
                .backgroundColor($r('app.color.primary'))
                .fontColor($r('app.color.text_on_primary'))
                .onClick(() => this.selectExcludeFolder())
            }
            .width('100%')
            // D组 #12 已选排除文件夹的 Chip 展示
            if (this.getExcludedList().length > 0) {
              Text('已排除:').fontSize(12).fontColor($r('app.color.text_hint'))
                .margin({ top: 6 }).alignSelf(ItemAlign.Start)
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
                ForEach(
                  this.getExcludedList(),
                  (folder: string) => {
                    Row({ space: 4 }) {
                      Text(folder)
                        .fontSize(11)
                        .fontColor($r('app.color.text_primary'))
                      Text('×')
                        .fontSize(13)
                        .fontColor($r('app.color.text_hint'))
                    }
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .margin({ right: 6, bottom: 6 })
                    .backgroundColor($r('app.color.bg_page'))
                    .borderRadius(14)
                    .onClick(() => this.removeExcludeFolder(folder))
                  },
                  (folder: string) => folder
                )
              }
              .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 排除的原始书名（书名完全相同才跳过）
          Column({ space: 6 }) {
            Text('排除的原始书名(逗号/换行分隔，书名完全相同才跳过)').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            AppTextInput({ text: this.excludedTitles, placeholder: '如 某某小说全集', onChangeCallback: (v: string) => (this.excludedTitles = v) })
          }
          .alignItems(HorizontalAlign.Start).width('100%')
          .backgroundColor($r('app.color.bg_card')).borderRadius(10).padding(12)

          // 排除的书名词汇（书名包含该词汇即跳过）
          Column({ space: 6 }) {
            Text('排除的书名词汇(逗号/换行分隔，书名包含该词汇即跳过)').fontSize(14).fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
            AppTextInput({ text: this.excludedTitleKeywords, placeholder: '如 番外;草稿', onChangeCallback: (v: string) => (this.excludedTitleKeywords = v) })
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
