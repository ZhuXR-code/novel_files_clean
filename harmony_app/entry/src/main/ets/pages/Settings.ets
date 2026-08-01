import { router, promptAction } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { AppContext } from '../utils/AppContext';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { ScanRunDao } from '../database/ScanRunDao';
import { KeywordReplaceDao } from '../database/KeywordReplaceDao';
import { DupRuleConfigDao } from '../database/DupRuleConfigDao';
import { ScanConfigDao } from '../database/ScanConfigDao';
import { ScanRun } from '../model/ScanRun';
import { ExportService } from '../service/ExportService';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { FontUtil } from '../utils/FontUtil';
import { ToastUtil } from '../utils/ToastUtil';

const THEME_MODE_KEY: string = 'settings_theme_mode';
const FONT_SCALE_KEY: string = 'settings_font_scale';
type ThemeMode = 'system' | 'light' | 'dark';
type FontScale = 'small' | 'standard' | 'large';

interface ThemeOption {
  label: string;
  value: ThemeMode;
}
interface FontOption {
  label: string;
  value: FontScale;
}

const THEME_OPTIONS: ThemeOption[] = [
  { label: '跟随系统', value: 'system' },
  { label: '浅色', value: 'light' },
  { label: '深色', value: 'dark' }
];
const FONT_OPTIONS: FontOption[] = [
  { label: '小', value: 'small' },
  { label: '标准', value: 'standard' },
  { label: '大', value: 'large' }
];

/**
 * 我的 Tab：外观 / 功能 / 数据 / 关于。
 * 对齐安卓端「我的」一级页。
 */
@Component
export struct MinePage {
  @State themeMode: ThemeMode = 'system';
  @State fontScale: FontScale = 'standard';
  @StorageProp('fontScale') fontScaleNum: number = 1.0;

  aboutToAppear(): void {
    const themeSaved: string = PreferencesUtil.getString(THEME_MODE_KEY, 'system');
    this.themeMode = (themeSaved === 'light' || themeSaved === 'dark') ? themeSaved as ThemeMode : 'system';
    const fontSaved: string = PreferencesUtil.getString(FONT_SCALE_KEY, 'standard');
    this.fontScale = (fontSaved === 'small' || fontSaved === 'large') ? fontSaved as FontScale : 'standard';
  }

  private go(url: string): void {
    router.pushUrl({ url: url }).catch((err: Error) => {
      LogUtil.e('MinePage', `跳转失败: ${err.message}`);
    });
  }

  /** 按全局字号缩放比换算基准字号 */
  private fs(base: number): number {
    return Math.round(base * this.fontScaleNum);
  }

  // ── 主题模式 ──
  private themeIndex(): string {
    return THEME_OPTIONS.find((o) => o.value === this.themeMode)?.label ?? '跟随系统';
  }

  private handleThemeChange(label: string): void {
    const opt = THEME_OPTIONS.find((o) => o.label === label);
    if (!opt) {
      return;
    }
    this.themeMode = opt.value;
    PreferencesUtil.putString(THEME_MODE_KEY, opt.value);
    try {
      const ctx = AppContext.get();
      if (ctx) {
        const appCtx = ctx.getApplicationContext();
        if (opt.value === 'dark') {
          appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        } else if (opt.value === 'light') {
          appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
        } else {
          appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        }
      }
    } catch (e) {
      LogUtil.e('MinePage', `切换主题失败: ${(e as Error).message}`);
    }
    ToastUtil.show(`主题已切换为「${opt.label}」`);
  }

  // ── 字号 ──
  private fontIndex(): string {
    return FONT_OPTIONS.find((o) => o.value === this.fontScale)?.label ?? '标准';
  }

  private handleFontChange(label: string): void {
    const opt = FONT_OPTIONS.find((o) => o.label === label);
    if (!opt) {
      return;
    }
    this.fontScale = opt.value;
    PreferencesUtil.putString(FONT_SCALE_KEY, opt.value);
    // 同步到 AppStorage，所有 @StorageProp('fontScale') 绑定的页面立即重渲染
    AppStorage.set(FontUtil.KEY, FontUtil.scaleFromString(opt.value));
    ToastUtil.show(`字号已切换为「${opt.label}」`);
  }

  // ── 预览滚动条 ──

  // ── 清除所有数据 ──
  private async clearAllData(): Promise<void> {
    AlertDialog.show({
      title: '清除所有数据',
      message: '将删除所有扫描记录、文库数据及缓存。此操作不可撤销，确定继续？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '确定清除',
        fontColor: $r('app.color.danger'),
        action: async () => {
          try {
            // 直接清空所有业务表，避免依赖 scan_run 级联而漏清
            await ScannedFileDao.deleteAll();
            await ScanRunDao.deleteAll();
            await KeywordReplaceDao.deleteAll();
            await DupRuleConfigDao.deleteAll();
            await ScanConfigDao.deleteAll();
            // G组 #25 彻底清理：同时清空操作日志
            await LogUtil.clear();
            ToastUtil.show('所有数据已清除');
            LogUtil.operation('设置', '清除所有数据完成（含操作日志）');
          } catch (e) {
            LogUtil.e('MinePage', `清除数据失败: ${(e as Error).message}`);
            ToastUtil.show('清除数据失败');
          }
        }
      }
    });
  }

  // ── 导出已标记文件 ──
  private async exportMarked(): Promise<void> {
    try {
      const runs = await ScanRunDao.getAll();
      if (runs.length === 0) {
        ToastUtil.show('没有可导出的文库');
        return;
      }
      const markedCount = await ScannedFileDao.countMarked();
      if (markedCount === 0) {
        ToastUtil.show('没有已标记的文件可导出');
        return;
      }
      // G组 #26 单文库直接导出，多文库让用户选择
      if (runs.length === 1) {
        const outPath = await ExportService.exportList(runs[0].id, 'marked', '标记文件');
        ToastUtil.show(`已导出 ${markedCount} 条记录`);
        LogUtil.operation('设置', `导出标记文件: ${outPath}`);
        return;
      }
      // 多文库：用 TextPickerDialog 选择
      const names: string[] = runs.map((r: ScanRun) => r.name || `文库${r.id}`);
      TextPickerDialog.show({
        range: names,
        selected: 0,
        onAccept: (value: TextPickerResult) => {
          const idxRaw: number | number[] = value.index as number | number[];
          const idx: number = Array.isArray(idxRaw) ? idxRaw[0] : idxRaw;
          const run: ScanRun = runs[idx];
          ExportService.exportList(run.id, 'marked', '标记文件').then((outPath: string) => {
            ToastUtil.show(`已导出文库「${run.name}」的标记文件`);
            LogUtil.operation('设置', `导出标记文件: ${outPath}`);
          }).catch((e: Error) => {
            LogUtil.e('MinePage', `导出失败: ${e.message}`);
            ToastUtil.show('导出失败');
          });
        }
      });
    } catch (e) {
      LogUtil.e('MinePage', `导出失败: ${(e as Error).message}`);
      ToastUtil.show('导出失败');
    }
  }

  build() {
    Column() {
      TopBar({ title: '我的', showBack: false })

      Scroll() {
        Column() {
          // ── 外观 ──
          Text('外观')
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 16, left: 16, bottom: 4 })
          Column({ space: 1 }) {
            // 主题模式（内联以响应 @State 变化）
            Row() {
              Text('主题模式').fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
              Blank()
              Select(THEME_OPTIONS.map((o): SelectOption => ({ value: o.label })))
                .value(this.themeIndex())
                .font({ size: 14 })
                .fontColor($r('app.color.text_secondary'))
                .margin({ right: 8 })
                .onSelect((_idx: number, label: string) => this.handleThemeChange(label))
            }
            .width('100%').height(52).padding({ left: 16, right: 16 })

            // 字号（内联以响应 @State 变化）
            Row() {
              Text('字号').fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
              Blank()
              Select(FONT_OPTIONS.map((o): SelectOption => ({ value: o.label })))
                .value(this.fontIndex())
                .font({ size: 14 })
                .fontColor($r('app.color.text_secondary'))
                .margin({ right: 8 })
                .onSelect((_idx: number, label: string) => this.handleFontChange(label))
            }
            .width('100%').height(52).padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          // ── 功能 ──
          Text('功能')
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 20, left: 16, bottom: 4 })
          Column({ space: 1 }) {
            this.item('关键词替换规则', 'pages/KeywordReplace')
            this.item('勾选重复规则', 'pages/DupRuleSettings')
          }
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          // ── 数据 ──
          Text('数据')
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 20, left: 16, bottom: 4 })
          Column({ space: 1 }) {
            this.actionItem('导出已标记文件', () => this.exportMarked())
            this.infoItem('目录授权', '每次扫描需重新选择（系统安全限制）')
            this.actionItemDanger('清除所有数据', () => this.clearAllData())
          }
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          // ── 关于 ──
          Text('关于')
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 20, left: 16, bottom: 4 })
          Column({ space: 1 }) {
            this.item('操作日志', 'pages/LogViewer')
            this.item('帮助', 'pages/Help')
            this.item('隐私协议', 'pages/PrivacyPolicy')
            this.infoItem('应用名称', '文包整理清理助手')
            this.infoItem('版本', '1.0.0')
            this.infoItem('运行形态', '纯本地（不联网）')
          }
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          Text('数据保存在应用私有目录，不会上传任何服务器。')
            .fontSize(this.fs(12))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 24, left: 16, right: 16, bottom: 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  // ── Builder 复用 ──
  @Builder
  item(label: string, url: string) {
    Row() {
      Text(label).fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
      Blank()
      Text('>').fontSize(this.fs(16)).fontColor($r('app.color.text_hint'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .onClick(() => this.go(url))
  }

  @Builder
  choiceItem(label: string, value: string, onClick: () => void) {
    Row() {
      Text(label).fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
      Blank()
      Text(value).fontSize(this.fs(15)).fontColor($r('app.color.text_hint'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  selectItem(label: string, value: string, options: string[], onChange: (label: string) => void) {
    Row() {
      Text(label).fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
      Blank()
      Select(options.map((o: string): SelectOption => ({ value: o })))
        .value(value)
        .font({ size: 14 })
        .fontColor($r('app.color.text_secondary'))
        .margin({ right: 8 })
        .onSelect((_idx: number, label: string) => onChange(label))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
  }

  @Builder
  actionItem(label: string, onClick: () => void) {
    Row() {
      Text(label).fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
      Blank()
      Text('>').fontSize(this.fs(16)).fontColor($r('app.color.text_hint'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  actionItemDanger(label: string, onClick: () => void) {
    Row() {
      Text(label).fontSize(this.fs(16)).fontColor($r('app.color.danger'))
      Blank()
      Text('>').fontSize(this.fs(16)).fontColor($r('app.color.text_hint'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  infoItem(label: string, value: string) {
    Row() {
      Text(label).fontSize(this.fs(15)).fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value).fontSize(this.fs(15)).fontColor($r('app.color.text_primary'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
  }
}
