import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { KeywordReplaceRule } from '../model/KeywordReplaceRule';
import { KeywordReplaceDao } from '../database/KeywordReplaceDao';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct KeywordReplace {
  @State scope: string = 'scan';
  @State rules: KeywordReplaceRule[] = [];
  @State editing: KeywordReplaceRule | null = null;
  @State editPattern: string = '';
  @State editReplacement: string = '';

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    const all: KeywordReplaceRule[] = await KeywordReplaceDao.getAll();
    this.rules = all
      .filter((r) => r.scope === this.scope)
      .sort((a, b) => a.sortOrder - b.sortOrder);
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
      promptAction.showToast({ message: '匹配串不能为空' });
      return;
    }
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
  }

  private async toggleEnabled(r: KeywordReplaceRule, enabled: boolean): Promise<void> {
    r.enabled = enabled;
    await KeywordReplaceDao.setEnabled(r.id, enabled);
  }

  private async deleteRule(r: KeywordReplaceRule): Promise<void> {
    await KeywordReplaceDao.delete(r.id);
    await this.load();
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('关键词替换')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
        Button('新增')
          .backgroundColor($r('app.color.primary'))
          .onClick(() => this.newRule())
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Button('扫描阶段')
          .backgroundColor(this.scope === 'scan' ? $r('app.color.primary') : $r('app.color.bg_card'))
          .fontColor(this.scope === 'scan' ? '#ffffff' : $r('app.color.text_primary'))
          .onClick(() => this.changeScope('scan'))
        Button('解析阶段')
          .backgroundColor(this.scope === 'parse' ? $r('app.color.primary') : $r('app.color.bg_card'))
          .fontColor(this.scope === 'parse' ? '#ffffff' : $r('app.color.text_primary'))
          .onClick(() => this.changeScope('parse'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

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
              .onClick(() => this.saveRule())
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(10)
        .margin({ left: 12, right: 12, top: 8 })
      }

      if (this.rules.length === 0) {
        Text('暂无规则')
          .fontSize(15)
          .fontColor($r('app.color.text_hint'))
          .margin({ top: 40 })
      } else {
        List() {
          ForEach(
            this.rules,
            (r: KeywordReplaceRule) => {
              ListItem() {
                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Toggle({ type: ToggleType.Switch, isOn: r.enabled }).onChange((v: boolean) => this.toggleEnabled(r, v))
                      .width(36)
                    Column({ space: 3 }) {
                      Text(`匹配: ${r.pattern}`)
                        .fontSize(14)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`替换: ${r.replacement || '(删除)'}`)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Button('编辑')
                      .height(32)
                      .onClick(() => this.editRule(r))
                    Button('删除')
                      .height(32)
                      .backgroundColor($r('app.color.danger'))
                      .onClick(() => this.deleteRule(r))
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(14)
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(10)
              }
              .padding({ left: 12, right: 12, bottom: 10 })
            },
            (r: KeywordReplaceRule) => r.id.toString()
          )
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
