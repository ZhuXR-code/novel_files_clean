import { preferences } from '@kit.ArkData';
import { AppContext } from './AppContext';

/**
 * 轻量键值偏好存储，对齐安卓端 util/PreferencesUtil。
 * 采用 @ohos.data.preferences（沙箱内同步 API），常用于保存：
 * 当前选中文库ID、关键词替换开关、排序偏好等轻量设置。
 * 扫描配置/关键词替换规则等结构化数据请走对应 Dao（持久在关系型库）。
 */
const PREF_NAME: string = 'file_scanner_prefs';

export class PreferencesUtil {
  public static readonly KW_SEED_DONE: string = 'keyword_seed_done';
  private static getStore(): preferences.Preferences | null {
    const ctx = AppContext.get();
    if (!ctx) {
      return null;
    }
    try {
      return preferences.getPreferencesSync(ctx, { name: PREF_NAME });
    } catch (e) {
      return null;
    }
  }

  public static getString(key: string, def: string): string {
    const store = PreferencesUtil.getStore();
    if (!store) {
      return def;
    }
    try {
      return store.getSync(key, def) as string;
    } catch (e) {
      return def;
    }
  }

  public static putString(key: string, value: string): void {
    const store = PreferencesUtil.getStore();
    if (!store) {
      return;
    }
    try {
      store.putSync(key, value);
      store.flushSync();
    } catch (e) {
      // 偏好存储失败不影响主流程
    }
  }

  public static getBoolean(key: string, def: boolean): boolean {
    const store = PreferencesUtil.getStore();
    if (!store) {
      return def;
    }
    try {
      return store.getSync(key, def) as boolean;
    } catch (e) {
      return def;
    }
  }

  public static putBoolean(key: string, value: boolean): void {
    const store = PreferencesUtil.getStore();
    if (!store) {
      return;
    }
    try {
      store.putSync(key, value);
      store.flushSync();
    } catch (e) {
      // 偏好存储失败不影响主流程
    }
  }

  public static getLong(key: string, def: number): number {
    const store = PreferencesUtil.getStore();
    if (!store) {
      return def;
    }
    try {
      return store.getSync(key, def) as number;
    } catch (e) {
      return def;
    }
  }

  public static putLong(key: string, value: number): void {
    const store = PreferencesUtil.getStore();
    if (!store) {
      return;
    }
    try {
      store.putSync(key, value);
      store.flushSync();
    } catch (e) {
      // 偏好存储失败不影响主流程
    }
  }
}
