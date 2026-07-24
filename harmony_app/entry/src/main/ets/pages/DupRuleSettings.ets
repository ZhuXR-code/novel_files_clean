import { LogUtil } from '../utils/LogUtil'
import { promptAction } from '@kit.ArkUI'
import { router } from '@kit.ArkUI'
import { DupRuleConfigDao } from '../database/DupRuleConfigDao'
import { DupRuleConfig } from '../model/DupRuleConfig'

interface EditCond {
  field: string
  op: string
  value: string
}

const FIELD_OPTIONS: Array<SelectOption> = [
  { value: 'file_name', label: '文件名' },
  { value: 'novel_name', label: '书名' },
  { value: 'author', label: '作者' },
  { value: 'progress', label: '进度' },
  { value: 'source', label: '来源站点' },
  { value: 'file_size', label: '文件大小(KB)' },
  { value: 'created_date', label: '创建时间(时间戳)' }
]

const OP_OPTIONS: Array<SelectOption> = [
  { value: 'eq', label: '等于' },
  { value: 'neq', label: '不等于' },
  { value: 'contains', label: '包含' },
  { value: 'not_contains', label: '不包含' },
  { value: 'starts_with', label: '开头为' },
  { value: 'ends_with', label: '结尾为' },
  { value: 'regex', label: '正则匹配' },
  { value: 'gt', label: '大于' },
  { value: 'gte', label: '大于等于' },
  { value: 'lt', label: '小于' },
  { value: 'lte', label: '小于等于' },
  { value: 'between', label: '介于(逗号分隔)' }
]

/**
 * 勾选重复规则配置页（对齐安卓端 DupRuleConfigScreen）。
 * - 内置 6 条规则：从 dup_rule_config 表读取开关（DB 驱动）。
 * - 自定义规则：支持新增 / 编辑 / 删除，条件为「字段+操作符+值」的 AND 组合，动作含「勾选/保护」。
 */
@Entry
@Component
struct DupRuleSettings {
  @State builtinRules: DupRuleConfig[] = []
  @State customRules: DupRuleConfig[] = []
  @State loading: boolean = false

  // 编辑器状态
  @State showEditor: boolean = false
  @State editingId: number = 0
  @State editName: string = ''
  @State editDesc: string = ''
  @State editAction: string = 'check'
  @State editConds: EditCond[] = []

  aboutToAppear(): void {
    this.load()
  }

  async load(): Promise<void> {
    this.loading = true
    try {
      const all: DupRuleConfig[] = await DupRuleConfigDao.getAll()
      const builtin: DupRuleConfig[] = []
      const custom: DupRuleConfig[] = []
      for (const r of all) {
        if (r.isBuiltin === 1) {
          builtin.push(r)
        } else {
          custom.push(r)
        }
      }
      this.builtinRules = builtin
      this.customRules = custom
    } catch (e) {
      LogUtil.e('DupRuleSettings', `加载规则失败: ${(e as Error).message}`)
    } finally {
      this.loading = false
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('勾选重复规则').fontSize(18).fontWeight(FontWeight.Bold).margin({ left: 8 })
      }
      .width('100%')
      .padding(12)
      .alignItems(VerticalAlign.Center)

      Text('选择「勾选重复」时应用的重复检测规则。内置规则为系统预设，自定义规则可灵活组合条件。')
        .fontSize(12).fontColor('#888')
        .width('100%').padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 6 }) {
          Text('内置规则').fontSize(14).fontWeight(FontWeight.Bold)
            .width('100%').padding({ left: 4, top: 4 })

          ForEach(this.builtinRules, (r: DupRuleConfig) => {
            this.ruleToggle(r.ruleName, r.description, r.enabled === 1, (v: boolean) => {
              this.toggleBuiltin(r, v)
            })
          }, (r: DupRuleConfig) => `b_${r.id.toString()}`)

          Row() {
            Text('自定义规则').fontSize(14).fontWeight(FontWeight.Bold)
            Blank()
            Button('+ 新增').fontSize(12).height(30).backgroundColor('#007aff').fontColor(Color.White)
              .onClick(() => this.openAdd())
          }
          .width('100%').padding({ left: 4, top: 12, right: 4 })

          if (this.customRules.length === 0) {
            Text('暂无自定义规则').fontSize(12).fontColor('#aaa').padding(8)
          }

          ForEach(this.customRules, (r: DupRuleConfig) => {
            this.customCard(r)
          }, (r: DupRuleConfig) => `c_${r.id.toString()}`)
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f5f5f5')

    if (this.showEditor) {
      this.editorPanel()
    }
  }

  @Builder
  ruleToggle(label: string, desc: string, isOn: boolean, onChange: (v: boolean) => void) {
    Row() {
      Column({ space: 2 }) {
        Text(label).fontSize(14).fontWeight(FontWeight.Medium)
        Text(desc).fontSize(11).fontColor('#888').lineHeight(16)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((v: boolean) => onChange(v))
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  customCard(r: DupRuleConfig) {
    Column({ space: 4 }) {
      Row() {
        Column({ space: 2 }) {
          Text(r.ruleName).fontSize(14).fontWeight(FontWeight.Medium)
          Text(r.action === 'protect' ? '动作：保护(不勾选)' : '动作：勾选(重复)')
            .fontSize(11).fontColor(r.action === 'protect' ? '#d2691e' : '#007aff')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (r.enabled === 0) {
          Text('已停用').fontSize(11).fontColor('#999').margin({ right: 8 })
        }
        Button('编辑').fontSize(12).height(30).onClick(() => this.openEdit(r))
        Button('删除').fontSize(12).height(30).backgroundColor('#ff3b30').fontColor(Color.White)
          .margin({ left: 6 }).onClick(() => this.deleteRule(r))
      }
      .width('100%')

      Text(this.condSummary(r.conditions))
        .fontSize(11).fontColor('#666')
        .width('100%')
        .padding({ top: 2 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(10)
  }

  private condSummary(json: string): string {
    const conds: EditCond[] = this.parseConds(json)
    if (conds.length === 0) {
      return '（无条件）'
    }
    return conds.map((c) => `${this.fieldLabel(c.field)} ${this.opLabel(c.op)} "${c.value}"`).join(' 且 ')
  }

  private fieldLabel(f: string): string {
    for (const o of FIELD_OPTIONS) {
      if (o.value === f) {
        return o.label as string
      }
    }
    return f
  }

  private opLabel(o: string): string {
    for (const p of OP_OPTIONS) {
      if (p.value === o) {
        return p.label as string
      }
    }
    return o
  }

  private parseConds(json: string): EditCond[] {
    const result: EditCond[] = []
    if (!json || json.trim().length === 0) {
      return result
    }
    const re: RegExp = /\{"field":"([^"]+)","op":"([^"]+)","value":"([^"]*)"\}/g
    let m: RegExpExecArray | null = re.exec(json)
    while (m !== null) {
      result.push({ field: m[1], op: m[2], value: m[3] })
      m = re.exec(json)
    }
    return result
  }

  async toggleBuiltin(r: DupRuleConfig, v: boolean): Promise<void> {
    r.enabled = v ? 1 : 0
    await DupRuleConfigDao.updateEnabled(r.id, r.enabled)
    LogUtil.i('DupRuleSettings', `内置规则 ${r.ruleKey} -> ${r.enabled}`)
  }

  // ===================== 编辑器 =====================
  private openAdd(): void {
    this.editingId = 0
    this.editName = ''
    this.editDesc = ''
    this.editAction = 'check'
    this.editConds = [{ field: 'file_name', op: 'contains', value: '' }]
    this.showEditor = true
  }

  private openEdit(r: DupRuleConfig): void {
    this.editingId = r.id
    this.editName = r.ruleName
    this.editDesc = r.description
    this.editAction = r.action
    this.editConds = this.parseConds(r.conditions)
    if (this.editConds.length === 0) {
      this.editConds = [{ field: 'file_name', op: 'contains', value: '' }]
    }
    this.showEditor = true
  }

  async deleteRule(r: DupRuleConfig): Promise<void> {
    await DupRuleConfigDao.delete(r.id)
    promptAction.showToast({ message: '已删除自定义规则', duration: 1500 })
    await this.load()
  }

  @Builder
  editorPanel() {
    Column() {
      Row() {
        Button('取消').onClick(() => { this.showEditor = false })
        Text(this.editingId === 0 ? '新增自定义规则' : '编辑自定义规则')
          .fontSize(16).fontWeight(FontWeight.Bold).margin({ left: 8 })
        Blank()
        Button('保存').backgroundColor('#007aff').fontColor(Color.White)
          .onClick(() => this.saveRule())
      }
      .width('100%').padding(12)

      Scroll() {
        Column({ space: 10 }) {
          Text('规则名称').fontSize(13).fontColor('#555')
          TextInput({ placeholder: '如：屏蔽某站点', text: this.editName })
            .onChange((v: string) => { this.editName = v })

          Text('说明').fontSize(13).fontColor('#555')
          TextInput({ placeholder: '可选', text: this.editDesc })
            .onChange((v: string) => { this.editDesc = v })

          Text('命中后动作').fontSize(13).fontColor('#555')
          Row({ space: 12 }) {
            this.actionRadio('勾选(标记重复)', 'check')
            this.actionRadio('保护(不勾选)', 'protect')
          }

          Row() {
            Text('条件（全部满足）').fontSize(13).fontColor('#555')
            Blank()
            Button('+ 条件').fontSize(12).height(30).backgroundColor('#34c759').fontColor(Color.White)
              .onClick(() => {
                this.editConds.push({ field: 'file_name', op: 'contains', value: '' })
                this.editConds = [...this.editConds]
              })
          }
          .width('100%')

          ForEach(this.editConds, (c: EditCond, idx: number) => {
            this.condEditor(c, idx)
          }, (c: EditCond, idx: number) => idx.toString())
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('92%')
    .backgroundColor(Color.White)
    .position({ x: 0, y: '8%' })
  }

  @Builder
  actionRadio(label: string, value: string) {
    Row({ space: 4 }) {
      Radio({ value: value, group: 'action' })
        .checked(this.editAction === value)
        .onChange((v: boolean) => { if (v) { this.editAction = value } })
      Text(label).fontSize(13)
    }
  }

  @Builder
  condEditor(c: EditCond, idx: number) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Select(FIELD_OPTIONS)
          .value(this.fieldLabel(c.field))
          .width('40%')
          .onSelect((i: number) => {
            c.field = FIELD_OPTIONS[i].value as string
            this.editConds = [...this.editConds]
          })
        Select(OP_OPTIONS)
          .value(this.opLabel(c.op))
          .width('40%')
          .onSelect((i: number) => {
            c.op = OP_OPTIONS[i].value as string
            this.editConds = [...this.editConds]
          })
        Button('删').fontSize(12).height(30).backgroundColor('#ff3b30').fontColor(Color.White)
          .onClick(() => {
            this.editConds.splice(idx, 1)
            this.editConds = [...this.editConds]
          })
      }
      .width('100%')

      TextInput({ placeholder: '值', text: c.value })
        .onChange((v: string) => {
          c.value = v
          this.editConds = [...this.editConds]
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#f0f0f0')
    .borderRadius(8)
  }

  private condsToJson(conds: EditCond[]): string {
    const items: Array<Record<string, string>> = conds
      .filter((c) => c.value.trim().length > 0)
      .map((c) => ({ field: c.field, op: c.op, value: c.value }))
    return JSON.stringify(items)
  }

  async saveRule(): Promise<void> {
    if (this.editName.trim().length === 0) {
      promptAction.showToast({ message: '请填写规则名称', duration: 1500 })
      return
    }
    const valid: EditCond[] = this.editConds.filter((c) => c.value.trim().length > 0)
    if (valid.length === 0) {
      promptAction.showToast({ message: '请至少配置一个条件的值', duration: 1500 })
      return
    }
    const rule: DupRuleConfig = new DupRuleConfig()
    rule.ruleName = this.editName.trim()
    rule.description = this.editDesc.trim()
    rule.action = this.editAction
    rule.conditions = this.condsToJson(this.editConds)
    rule.isBuiltin = 0
    rule.enabled = 1
    if (this.editingId !== 0) {
      rule.id = this.editingId
      await DupRuleConfigDao.update(rule)
    } else {
      await DupRuleConfigDao.insert(rule)
    }
    this.showEditor = false
    promptAction.showToast({ message: '已保存', duration: 1500 })
    await this.load()
  }
}
