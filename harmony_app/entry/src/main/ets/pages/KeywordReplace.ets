import { KeywordReplaceRule } from '../model/KeywordReplaceRule';
import { KeywordReplaceDao } from '../database/KeywordReplaceDao';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { ToastUtil } from '../utils/ToastUtil';

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

  private newRule(): void {
    const r: KeywordReplaceRule = new KeywordReplaceRule();
    r.scope = this.scope;
    r.enabled = true;
    this.editing = r;
    this.editPattern = '';
    this.editReplacement = '';
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

  private deleteRule(r: KeywordReplaceRule): void {
    AlertDialog.show({
      title: '确认删除规则？',
      message: `匹配: ${r.pattern}\n删除后不可恢复，此规则将不再生效。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.confirmDelete(r);
        }
      }
    });
  }

  private async confirmDelete(r: KeywordReplaceRule): Promise<void> {
    try {
      await KeywordReplaceDao.delete(r.id);
      LogUtil.operation('关键词替换', `删除规则 id=${r.id} pattern=${r.pattern}`);
      await this.load();
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
          .backgroundColor($r('app.color.danger'))
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
            .backgroundColor(this.scope === 'scan' ? $r('app.color.primary') : $r('app.color.bg_card'))
            .fontColor(this.scope === 'scan' ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
            .onClick(() => this.changeScope('scan'))
          Button('解析阶段')
            .fontSize(13)
            .height(34)
            .layoutWeight(1)
            .backgroundColor(this.scope === 'parse' ? $r('app.color.primary') : $r('app.color.bg_card'))
            .fontColor(this.scope === 'parse' ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
            .onClick(() => this.changeScope('parse'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })

        Scroll() {
          Column({ space: 8 }) {
            // 编辑区
            if (this.editing) {
              Column({ space: 10 }) {
                Text(this.editing.id > 0 ? '编辑规则' : '新增规则')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                TextInput({ text: this.editPattern, placeholder: '匹配串（字面量）' })
                  .onChange((v: string) => (this.editPattern = v))
                TextInput({ text: this.editReplacement, placeholder: '替换为（留空=删除）' })
                  .onChange((v: string) => (this.editReplacement = v))
                Row({ space: 12 }) {
                  Button('取消').layoutWeight(1).onClick(() => (this.editing = null))
                  Button('保存')
                    .layoutWeight(1)
                    .backgroundColor($r('app.color.primary'))
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
            Text(`内置规则（${this.builtinRules.length} 条，不可删除）`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 4, top: 4, bottom: 2 })

            ForEach(
              this.builtinRules,
              (r: KeywordReplaceRule) => {
                this.builtinRuleCard(r)
              },
              (r: KeywordReplaceRule) => `b_${r.id.toString()}`
            )

            // 自定义规则区
            Row() {
              Text('自定义规则')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_secondary'))
              Blank()
            }
            .width('100%')
            .padding({ left: 4, top: 8, bottom: 2 })

            if (this.customRules.length === 0) {
              Text('暂无自定义规则，点击右上角「新增」创建')
                .fontSize(12)
                .fontColor($r('app.color.text_hint'))
                .padding(8)
            }

            ForEach(
              this.customRules,
              (r: KeywordReplaceRule) => {
                this.customRuleCard(r)
              },
              (r: KeywordReplaceRule) => `c_${r.id.toString()}`
            )
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 16 })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .width('100%')
    .height('100%')
  }
}
