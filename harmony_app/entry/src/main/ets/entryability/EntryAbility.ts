import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { RdbHelper } from '../database/RdbHelper';
import { AppContext } from '../utils/AppContext';
import { LogUtil } from '../utils/LogUtil';
import { KeywordReplace } from '../utils/KeywordReplace';
import { KeywordReplaceDao } from '../database/KeywordReplaceDao';
import { DupRuleConfigDao } from '../database/DupRuleConfigDao';
import { DupRuleConfig } from '../model/DupRuleConfig';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { FilePermissionUtil } from '../utils/FilePermissionUtil';
import { FontUtil } from '../utils/FontUtil';

/**
 * 应用入口 Ability。负责初始化数据库单例、保存全局 Context。
 */
export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    AppContext.set(this.context);
    // 初始化全局字号缩放（AppStorage 共享，各页面通过 @StorageProp 绑定）
    const fontSaved: string = PreferencesUtil.getString('settings_font_scale', 'standard');
    AppStorage.setOrCreate(FontUtil.KEY, FontUtil.scaleFromString(fontSaved));
    // 初始化全局预览滚动条方向（AppStorage 共享，FilePreview 通过 @StorageProp 绑定）
    const scrollbarSaved: string = PreferencesUtil.getString('preview_scrollbar_mode', 'vertical');
    AppStorage.setOrCreate('previewScrollbarMode', scrollbarSaved);
    try {
      await RdbHelper.getInstance(this.context);
      LogUtil.i('EntryAbility', '数据库初始化完成');
      await this.seedDefaultKeywordRules();
      await this.seedDefaultDupRules();
      // 激活已持久化的文件访问权限（应用重启后仍可访问/删除之前选中的文件夹）
      await FilePermissionUtil.activatePersistedPermissions();
    } catch (e) {
      // 打印完整错误（含堆栈），便于定位初始化失败的真实原因
      LogUtil.e('EntryAbility', `数据库初始化失败: ${(e as Error)?.message ?? '未知错误'}\nstack: ${(e as Error)?.stack ?? ''}`);
    }
  }

  /**
   * 补齐缺失的预置关键词替换规则（幂等）：按 pattern 判断，仅插入库中尚不存在的默认项。
   * 首次为空时整批写入；后续新增预置项也会自动补进已安装实例，无需清数据。
   */
  private async seedDefaultKeywordRules(): Promise<void> {
    try {
      let added: number = 0;
      for (const rule of KeywordReplace.DEFAULT_KEYWORD_RULES) {
        const n: number = await KeywordReplaceDao.countByScopeAndPattern(rule.scope, rule.pattern);
        if (n === 0) {
          await KeywordReplaceDao.insert(rule);
          added++;
        } else {
          // 旧库内置规则可能未标记 is_builtin，补刷为内置（显示在内置区且不可删除）
          await KeywordReplaceDao.markBuiltinByPattern(rule.scope, rule.pattern);
        }
      }
      if (added > 0) {
        LogUtil.i('EntryAbility', `已补齐 ${added} 条默认关键词替换规则`);
      }
      PreferencesUtil.putBoolean(PreferencesUtil.KW_SEED_DONE, true);
    } catch (e) {
      LogUtil.e('EntryAbility', `默认关键词规则写入失败: ${(e as Error).message}`);
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // 确保数据库就绪后再加载首页：onCreate 是 async 且不被框架 await，
    // 若不在此处等待，首页 aboutToAppear 可能在 DB 初始化完成前调用 DAO，触发 "getStore of null"。
    try {
      await RdbHelper.getInstance(this.context);
    } catch (e) {
      LogUtil.e('EntryAbility', `数据库初始化失败(窗口阶段): ${(e as Error)?.message ?? '未知错误'}`);
    }
    windowStage.loadContent('pages/MainTabs', (err: Error) => {
      if (err.message) {
        LogUtil.e('EntryAbility', `加载首页失败: ${err.message}`);
        return;
      }
      // 保存主窗口引用（备用）
      try {
        const mainWindow: window.Window = windowStage.getMainWindowSync();
        AppContext.setMainWindow(mainWindow);
      } catch (e) {
        LogUtil.e('EntryAbility', `获取主窗口失败: ${(e as Error).message}`);
      }
      // 读取已保存的主题偏好并应用到应用（setColorMode 为应用级，立即生效且持久至进程结束）
      try {
        const theme: string = PreferencesUtil.getString('settings_theme_mode', 'system');
        if (theme === 'dark') {
          this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        } else if (theme === 'light') {
          this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
        } else {
          // 'system' 跟随系统
          this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        }
      } catch (e) {
        LogUtil.e('EntryAbility', `应用主题失败: ${(e as Error).message}`);
      }
    });
  }

  /**
   * 补齐内置去重规则（幂等）：按 ruleKey 判断，仅插入库中尚不存在的项。
   * 首次为空时整批写入；与安卓端 BuiltinDupRule 一一对应。
   */
  private async seedDefaultDupRules(): Promise<void> {
    try {
      // 先清理历史上因缺少 UNIQUE 约束、每次启动都重新插入而重复的内置规则（每个 rule_key 只保留一条）
      try {
        await DupRuleConfigDao.dedupByKey();
      } catch (e) {
        LogUtil.e('EntryAbility', `清理重复内置规则失败: ${(e as Error).message}`);
      }
      const builtins: DupRuleConfig[] = [
        EntryAbility.builtin('rule1', '完全相等去重', '小说名+作者+进度+文件大小 完全一致视为重复', 1),
        EntryAbility.builtin('rule2', '数字进度对比', '有纯数字进度时，数字大者保留', 2),
        EntryAbility.builtin('rule3a', '中文进度/完结优先', '含中文进度或完结关键词者优先保留', 3),
        EntryAbility.builtin('rule3b', '番外特例', '完结+数字番外 按 N 最大保留', 4),
        EntryAbility.builtin('rule4', '大文件保护', '同组内文件最大者不勾选(保护)', 5),
        EntryAbility.builtin('rule5', '完结+番外覆盖', '完结+N番外 按 N 最大保留(覆盖规则3A)', 6)
      ];
      for (const r of builtins) {
        await DupRuleConfigDao.insertIfNotExists(r);
      }
      LogUtil.i('EntryAbility', `已确保 ${builtins.length} 条内置去重规则`);
    } catch (e) {
      LogUtil.e('EntryAbility', `默认去重规则写入失败: ${(e as Error).message}`);
    }
  }

  private static builtin(ruleKey: string, ruleName: string, description: string, sortOrder: number): DupRuleConfig {
    const r: DupRuleConfig = new DupRuleConfig();
    r.ruleKey = ruleKey;
    r.ruleName = ruleName;
    r.description = description;
    r.isBuiltin = 1;
    r.enabled = 1;
    r.sortOrder = sortOrder;
    r.action = 'check';
    r.conditions = '[]';
    return r;
  }
}
