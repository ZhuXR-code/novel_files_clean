import { AbilityConstant, UIAbility, Want, window } from '@kit.AbilityKit';
import { RdbHelper } from '../database/RdbHelper';
import { AppContext } from '../utils/AppContext';
import { LogUtil } from '../utils/LogUtil';
import { KeywordReplace } from '../utils/KeywordReplace';
import { KeywordReplaceDao } from '../database/KeywordReplaceDao';
import { PreferencesUtil } from '../utils/PreferencesUtil';

/**
 * 应用入口 Ability。负责初始化数据库单例、保存全局 Context。
 */
export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    AppContext.set(this.context);
    try {
      await RdbHelper.getInstance(this.context);
      LogUtil.i('EntryAbility', '数据库初始化完成');
      await this.seedDefaultKeywordRules();
    } catch (e) {
      LogUtil.e('EntryAbility', `数据库初始化失败: ${(e as Error).message}`);
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

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: Error) => {
      if (err.code) {
        LogUtil.e('EntryAbility', `加载首页失败: ${err.code} ${err.message}`);
      }
    });
  }
}
