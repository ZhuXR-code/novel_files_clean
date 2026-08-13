import { KeywordReplaceRule } from '../model/KeywordReplaceRule';
import { KeywordReplaceDao } from '../database/KeywordReplaceDao';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { AppTextInput } from '../components/AppTextInput';
import { ToastUtil } from '../utils/ToastUtil';
import { promptAction } from '@kit.ArkUI';

/**
 * 关键词替换规则页（对齐安卓端 KeywordReplaceScreen）。
 *
 * 结构对齐 DupRuleSettings：使用 @State 分数组 + Scroll/Column 容器，
 * 避免 List 内 if 块混合 ListItem+ForEach 导致的 ArkTS 组件树崩溃。
 */
@Entry
@Component
struct KeywordReplace {
  @State scope: string = 'scan';
  @State builtinRules: KeywordReplaceRule[] = [];
  @State customRules: KeywordReplaceRule[] = [];
  @State editing: KeywordReplaceRule | null = null;
  @State editPattern: string = '';
  @State editReplacement: string = '';
  @State batching: boolean = false;
  @State batchMode: string = 'remove'; // remove | replace
  @State batchText: string = '';
  @State batchEnabled: boolean = true;
  @State searchOpen: boolean = false;
  @State searchQuery: string = '';
  // 列表版本号：每次批量操作/增删后自增，拼入 ForEach key 强制重建卡片，
  // 保证 Toggle 视觉状态一定刷新（部分真机上仅靠对象字段变更不触发重建）
  @State listVersion: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      // 确保内置规则已补齐（防止 EntryAbility 初始化时序问题导致页面为空）
      await KeywordReplaceDao.ensureBuiltinSeeded();
      const all: KeywordReplaceRule[] = await KeywordReplaceDao.getAll();
      const builtin: KeywordReplaceRule[] = [];
      const custom: KeywordReplaceRule[] = [];
      for (const r of all) {
        if (r.scope !== this.scope) {
          continue;
        }
        if (r.isBuiltin === 1) {
          builtin.push(r);
        } else {
          custom.push(r);
        }
      }
      builtin.sort((a, b) => a.sortOrder - b.sortOrder);
      custom.sort((a, b) => a.sortOrder - b.sortOrder);
      this.builtinRules = builtin;
      this.customRules = custom;
    } catch (e) {
      LogUtil.e('KeywordReplace', `加载规则失败: ${(e as Error).message}`);
      ToastUtil.show(`加载失败: ${(e as Error).message}`);
    }
  }

  private async changeScope(s: string): Promise<void> {
    this.scope = s;
    this.editing = null;
    await this.load();
  }

  private filteredBuiltin(): KeywordReplaceRule[] {
    return this.filterByQuery(this.builtinRules);
  }

  private filteredCustom(): KeywordReplaceRule[] {
    return this.filterByQuery(this.customRules);
  }

  private filterByQuery(list: KeywordReplaceRule[]): KeywordReplaceRule[] {
    const kw: string = this.searchQuery.trim().toLowerCase();
    if (kw.length === 0) {
      return list;
    }
    return list.filter((r: KeywordReplaceRule): boolean => {
      return r.pattern.toLowerCase().indexOf(kw) >= 0 ||
        r.replacement.toLowerCase().indexOf(kw) >= 0;
    });
  }

  private toggleSearch(): void {
    this.searchOpen = !this.searchOpen;
    if (!this.searchOpen) {
      this.searchQuery = '';
    }
  }

  private newRule(): void {
    const r: KeywordReplaceRule = new KeywordReplaceRule();
    r.scope = this.scope;
    r.enabled = true;
    this.editing = r;
    this.editPattern = '';
    this.editReplacement = '';
  }

  private openBatch(): void {
    this.batching = true;
    this.batchMode = 'remove';
    this.batchText = '';
    this.batchEnabled = true;
  }

  private async saveBatch(): Promise<void> {
    const lines: string[] = this.batchText
      .split('\n')
      .map((s: string) => s.trim())
      .filter((s: string) => s.length > 0);
    if (lines.length === 0) {
      ToastUtil.show('请至少填写一条');
      return;
    }
    if (this.batchMode === 'replace') {
      const bad: string | undefined = lines.find((line: string) => {
        const idx: number = line.indexOf('||');
        return idx <= 0 || line.substring(0, idx).trim().length === 0;
      });
      if (bad !== undefined) {
        ToastUtil.show('替换模式每行需包含 || 分隔符，且被替换词不可为空');
        return;
      }
    }
    try {
      let order: number = await KeywordReplaceDao.maxSortOrder(this.scope);
      for (const line of lines) {
        const r: KeywordReplaceRule = new KeywordReplaceRule();
        r.scope = this.scope;
        r.enabled = this.batchEnabled;
        r.createdAt = Date.now();
        if (this.batchMode === 'replace') {
          const idx: number = line.indexOf('||');
          r.pattern = line.substring(0, idx).trim();
          r.replacement = line.substring(idx + 2).trim();
        } else {
          r.pattern = line;
          r.replacement = '';
        }
        r.sortOrder = ++order;
        await KeywordReplaceDao.insert(r);
      }
      LogUtil.operation('关键词替换', `批量新增 ${lines.length} 条 scope=${this.scope} mode=${this.batchMode}`);
      this.batching = false;
      await this.load();
      this.listVersion++;
    } catch (e) {
      LogUtil.e('KeywordReplace', `批量新增失败: ${(e as Error).message}`);
      ToastUtil.show(`保存失败: ${(e as Error).message}`);
    }
  }

  private editRule(r: KeywordReplaceRule): void {
    this.editing = r;
    this.editPattern = r.pattern;
    this.editReplacement = r.replacement;
  }

  private async saveRule(): Promise<void> {
    if (!this.editing) {
      return;
    }
    if (this.editPattern.trim().length === 0) {
      ToastUtil.show('匹配串不能为空');
      return;
    }
    try {
      this.editing.scope = this.scope;
      this.editing.pattern = this.editPattern.trim();
      this.editing.replacement = this.editReplacement;
      if (this.editing.id === 0) {
        this.editing.createdAt = Date.now();
        const maxSo: number = await KeywordReplaceDao.maxSortOrder(this.scope);
        this.editing.sortOrder = maxSo + 1;
        await KeywordReplaceDao.insert(this.editing);
      } else {
        await KeywordReplaceDao.update(this.editing);
      }
      LogUtil.operation('关键词替换', `保存规则 scope=${this.scope}`);
      this.editing = null;
      await this.load();
      this.listVersion++;
    } catch (e) {
      LogUtil.e('KeywordReplace', `保存规则失败: ${(e as Error).message}`);
      ToastUtil.show(`保存失败: ${(e as Error).message}`);
    }
  }

  private async toggleEnabled(r: KeywordReplaceRule, enabled: boolean): Promise<void> {
    try {
      r.enabled = enabled;
      await KeywordReplaceDao.setEnabled(r.id, enabled);
    } catch (e) {
      LogUtil.e('KeywordReplace', `切换开关失败: ${(e as Error).message}`);
      ToastUtil.show('操作失败');
      r.enabled = !enabled;
    }
  }

  /** 当前搜索命中的全部规则（内置 + 自定义），批量操作的作用范围。 */
  private currentVisible(): KeywordReplaceRule[] {
    return this.filteredBuiltin().concat(this.filteredCustom());
  }

  /** 当前列表中已启用的规则数量。 */
  private enabledVisibleCount(): number {
    return this.currentVisible().filter((r: KeywordReplaceRule): boolean => r.enabled).length;
  }

  /**
   * 批量启用 / 不启用：仅对当前列表（搜索命中）的规则生效，写入数据库，
   * 返回上一页再进来状态依旧保留。
   * 确认弹窗用 promptAction.showDialog（本应用其它页面已在真机验证可用）；
   * 此前用 AlertDialog.show，部分真机（HarmonyOS 6.x）上不弹或按钮回调不触发，
   * 表现为「点击批量启用/不启用，下方开关无变化」。
   */
  private async batchSetEnabled(enabled: boolean): Promise<void> {
    const targets: KeywordReplaceRule[] = this.currentVisible();
    if (targets.length === 0) {
      ToastUtil.show('当前没有可操作的规则');
      return;
    }
    const action: string = enabled ? '启用' : '不启用';
    const searching: boolean = this.searchQuery.trim().length > 0;
    const range: string = searching ? `搜索结果中的 ${targets.length} 条` : `当前 ${targets.length} 条`;
    let confirmed: boolean = false;
    try {
      const res: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: `批量${action}`,
        message: `确定将${range}规则设为「${action}」？`,
        buttons: [
          { text: '取消', color: $r('app.color.text_secondary') },
          { text: '确定', color: $r('app.color.primary') }
        ]
      });
      confirmed = res.index === 1;
    } catch (e) {
      LogUtil.e('KeywordReplace', `批量确认弹窗异常: ${(e as Error).message}`);
      return;
    }
    if (!confirmed) {
      return;
    }
    try {
      const ids: number[] = targets.map((r: KeywordReplaceRule): number => r.id);
      await KeywordReplaceDao.setEnabledBatch(ids, enabled);
      LogUtil.operation('关键词替换', `批量${action} ${ids.length} 条 scope=${this.scope}`);
      ToastUtil.show(`已${action} ${ids.length} 条规则`);
    } catch (e) {
      LogUtil.e('KeywordReplace', `批量操作失败: ${(e as Error).message}`);
      ToastUtil.show(`操作失败: ${(e as Error).message}`);
    }
    // 无论成败都重新加载：成功时同步数据库最新状态，失败时回滚内存改动；
    // 并自增 listVersion 强制 ForEach 重建卡片，确保 Toggle 开关视觉刷新
    await this.load();
    this.listVersion++;
  }

  private async deleteRule(r: KeywordReplaceRule): Promise<void> {
    // 与批量操作一致改用 promptAction.showDialog（AlertDialog.show 部分真机不弹）
    let confirmed: boolean = false;
    try {
      const res: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: '确认删除规则？',
        message: `匹配: ${r.pattern}\n删除后不可恢复，此规则将不再生效。`,
        buttons: [
          { text: '取消', color: $r('app.color.text_secondary') },
          { text: '确认删除', color: $r('app.color.danger') }
        ]
      });
      confirmed = res.index === 1;
    } catch (e) {
      LogUtil.e('KeywordReplace', `删除确认弹窗异常: ${(e as Error).message}`);
      return;
    }
    if (confirmed) {
      this.confirmDelete(r);
    }
  }

  private async confirmDelete(r: KeywordReplaceRule): Promise<void> {
    try {
      await KeywordReplaceDao.delete(r.id);
      LogUtil.operation('关键词替换', `删除规则 id=${r.id} pattern=${r.pattern}`);
      await this.load();
      this.listVersion++;
    } catch (e) {
      LogUtil.e('KeywordReplace', `删除规则失败: ${(e as Error).message}`);
      ToastUtil.show(`删除失败: ${(e as Error).message}`);
    }
  }

  @Builder
  builtinRuleCard(r: KeywordReplaceRule) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Switch, isOn: r.enabled })
        .onChange((v: boolean) => this.toggleEnabled(r, v))
        .width(36)
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(`匹配: ${r.pattern}`)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('内置')
            .fontSize(10)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .borderRadius(3)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        }
        .width('100%')
        Text(`替换: ${r.replacement.length > 0 ? r.replacement : '(删除)'}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  customRuleCard(r: KeywordReplaceRule) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Switch, isOn: r.enabled })
          .onChange((v: boolean) => this.toggleEnabled(r, v))
          .width(36)
        Column({ space: 3 }) {
          Text(`匹配: ${r.pattern}`)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`替换: ${r.replacement.length > 0 ? r.replacement : '(删除)'}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        Blank()
        Button('编辑')
          .fontSize(12)
          .height(30)
          .onClick(() => this.editRule(r))
        Button('删除')
          .fontSize(12)
          .height(30)
          .backgroundColor($r('app.color.btn_danger_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .onClick(() => this.deleteRule(r))
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }

  onBackPress(): boolean {
    if (this.editing) {
      this.editing = null;
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      Column({ space: 8 }) {
        TopBar({ title: '关键词替换', rightText: '新增', onRight: () => this.newRule() })

        Row({ space: 8 }) {
          Button('扫描阶段')
            .fontSize(13)
            .height(34)
            .layoutWeight(1)
            .backgroundColor(this.scope === 'scan' ? $r('app.color.btn_primary_bg') : $r('app.color.bg_card'))
            .fontColor(this.scope === 'scan' ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
            .onClick(() => this.changeScope('scan'))
          Button('解析阶段')
            .fontSize(13)
            .height(34)
            .layoutWeight(1)
            .backgroundColor(this.scope === 'parse' ? $r('app.color.btn_primary_bg') : $r('app.color.bg_card'))
            .fontColor(this.scope === 'parse' ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
            .onClick(() => this.changeScope('parse'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })

        // 可展开 / 折叠的搜索栏
        Row({ space: 8 }) {
          Text('🔍')
            .fontSize(13)
          Text(this.searchOpen ? '收起搜索' : '搜索规则')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          Text(this.searchOpen ? '▲' : '▼')
            .fontSize(10)
            .fontColor($r('app.color.text_hint'))
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 2 })
        .onClick(() => this.toggleSearch())

        if (this.searchOpen) {
          AppTextInput({ text: this.searchQuery, placeholder: '按 查找 / 替换 内容过滤规则…', onChangeCallback: (v: string) => (this.searchQuery = v) })
        }

        // 批量启用 / 不启用：仅作用于当前列表（搜索命中）的规则
        if (this.currentVisible().length > 0) {
          Row({ space: 8 }) {
            Text(`当前 ${this.currentVisible().length} 条（已启用 ${this.enabledVisibleCount()} / 未启用 ${this.currentVisible().length - this.enabledVisibleCount()}）`)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            Button('批量启用')
              .fontSize(12)
              .height(28)
              .padding({ left: 10, right: 10 })
              .backgroundColor($r('app.color.bg_card'))
              .fontColor($r('app.color.primary'))
              .onClick(() => this.batchSetEnabled(true))
            Button('批量不启用')
              .fontSize(12)
              .height(28)
              .padding({ left: 10, right: 10 })
              .backgroundColor($r('app.color.bg_card'))
              .fontColor($r('app.color.text_secondary'))
              .onClick(() => this.batchSetEnabled(false))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        }

        Scroll() {
          Column({ space: 8 }) {
            // 编辑区
            if (this.editing) {
              Column({ space: 10 }) {
                Text(this.editing.id > 0 ? '编辑规则' : '新增规则')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                AppTextInput({ text: this.editPattern, placeholder: '匹配串（字面量）', onChangeCallback: (v: string) => (this.editPattern = v) })
                AppTextInput({ text: this.editReplacement, placeholder: '替换为（留空=删除）', onChangeCallback: (v: string) => (this.editReplacement = v) })
                Row({ space: 12 }) {
                  Button('取消').layoutWeight(1).onClick(() => (this.editing = null))
                  Button('保存')
                    .layoutWeight(1)
                    .backgroundColor($r('app.color.btn_primary_bg'))
                    .fontColor($r('app.color.text_on_primary'))
                    .onClick(() => this.saveRule())
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.bg_card'))
              .borderRadius(10)
            }

            // 内置规则区
            Text(`内置规则（${this.filteredBuiltin().length} 条，不可删除）`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 4, top: 4, bottom: 2 })

            ForEach(
              this.filteredBuiltin(),
              (r: KeywordReplaceRule) => {
                this.builtinRuleCard(r)
              },
              // key 中加入 listVersion + enabled 状态，批量启用/禁用后强制重建卡片，确保 Toggle 视觉刷新
              (r: KeywordReplaceRule) => `b_${this.listVersion}_${r.id}_${r.enabled ? 1 : 0}`
            )

            // 自定义规则区
            Row() {
              Text('自定义规则')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_secondary'))
              Blank()
              Button('批量新增')
                .fontSize(12)
                .height(30)
                .backgroundColor($r('app.color.primary_light'))
                .fontColor($r('app.color.primary'))
                .onClick(() => this.openBatch())
            }
            .width('100%')
            .padding({ left: 4, top: 8, bottom: 2 })

            // 批量新增编辑区
            if (this.batching) {
              Column({ space: 10 }) {
                Text('批量新增关键词替换规则')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Row({ space: 12 }) {
                  Button('去掉关键词')
                    .fontSize(13)
                    .height(34)
                    .layoutWeight(1)
                    .backgroundColor(this.batchMode === 'remove' ? $r('app.color.btn_primary_bg') : $r('app.color.bg_card'))
                    .fontColor(this.batchMode === 'remove' ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
                    .onClick(() => (this.batchMode = 'remove'))
                  Button('替换关键词')
                    .fontSize(13)
                    .height(34)
                    .layoutWeight(1)
                    .backgroundColor(this.batchMode === 'replace' ? $r('app.color.btn_primary_bg') : $r('app.color.bg_card'))
                    .fontColor(this.batchMode === 'replace' ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
                    .onClick(() => (this.batchMode = 'replace'))
                }
                .width('100%')

                Text(this.batchMode === 'remove'
                  ? '每行一个关键词，作为「删除替换」处理（整行内容将被移除）。'
                  : '每行一条，用 || 分隔「被替换词」和「替换成词」，如 AAA||B 表示 AAA 替换成 B。')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')

                TextArea({ text: this.batchText, placeholder: this.batchMode === 'remove' ? '每行一条关键词' : '每行一条，如 AAA||B' })
                  .onChange((v: string) => (this.batchText = v))
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_secondary'))
                  .height(180)
                  .width('100%')

                Row({ space: 8 }) {
                  Toggle({ type: ToggleType.Switch, isOn: this.batchEnabled })
                    .onChange((v: boolean) => (this.batchEnabled = v))
                    .width(36)
                  Text('启用')
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                  Blank()
                  Button('取消')
                    .layoutWeight(1)
                    .height(36)
                    .onClick(() => (this.batching = false))
                  Button('保存')
                    .layoutWeight(1)
                    .height(36)
                    .backgroundColor($r('app.color.btn_primary_bg'))
                    .fontColor($r('app.color.text_on_primary'))
                    .onClick(() => this.saveBatch())
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.bg_card'))
              .borderRadius(10)
            }

            if (this.filteredCustom().length === 0) {
              Text(this.searchQuery.trim().length > 0 ? '无匹配规则' : '暂无自定义规则，点击右上角「新增」创建')
                .fontSize(12)
                .fontColor($r('app.color.text_hint'))
                .padding(8)
            }

            ForEach(
              this.filteredCustom(),
              (r: KeywordReplaceRule) => {
                this.customRuleCard(r)
              },
              // key 中加入 listVersion + enabled 状态，批量启用/禁用后强制重建卡片，确保 Toggle 视觉刷新
              (r: KeywordReplaceRule) => `c_${this.listVersion}_${r.id}_${r.enabled ? 1 : 0}`
            )
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 16 })
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }
}
