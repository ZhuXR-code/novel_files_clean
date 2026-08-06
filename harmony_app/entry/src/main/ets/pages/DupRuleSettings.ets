import { LogUtil } from '../utils/LogUtil'
import { promptAction } from '@kit.ArkUI'
import { DupRuleConfigDao } from '../database/DupRuleConfigDao'
import { DupRuleConfig } from '../model/DupRuleConfig'
import { TopBar } from '../components/TopBar'
import { AppTextInput } from '../components/AppTextInput'
import { ToastUtil } from '../utils/ToastUtil';

interface EditCond {
  field: string
  op: string
  value: string
}

interface OptionChoice {
  key: string
  label: string
}

const FIELD_CHOICES: OptionChoice[] = [
  { key: 'file_name', label: '文件名' },
  { key: 'novel_name', label: '书名' },
  { key: 'author', label: '作者' },
  { key: 'progress', label: '进度' },
  { key: 'source', label: '来源站点' },
  { key: 'file_size', label: '文件大小(字节)' },
  { key: 'created_date', label: '创建时间(时间戳)' }
]

const OP_CHOICES: OptionChoice[] = [
  { key: 'eq', label: '等于' },
  { key: 'neq', label: '不等于' },
  { key: 'contains', label: '包含' },
  { key: 'not_contains', label: '不包含' },
  { key: 'starts_with', label: '开头为' },
  { key: 'ends_with', label: '结尾为' },
  { key: 'regex', label: '正则匹配' },
  { key: 'gt', label: '大于' },
  { key: 'gte', label: '大于等于' },
  { key: 'lt', label: '小于' },
  { key: 'lte', label: '小于等于' },
  { key: 'between', label: '介于(逗号分隔)' }
]

// 本 SDK 的 SelectOption 仅含 value(即下拉显示文本)，故用单独数组保存内部 key
const FIELD_OPTIONS: Array<SelectOption> = FIELD_CHOICES.map((c): SelectOption => ({ value: c.label }))
const OP_OPTIONS: Array<SelectOption> = OP_CHOICES.map((c): SelectOption => ({ value: c.label }))

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
  // F组 #20 正则测试器
  @State regexPattern: string = ''
  @State regexTestInput: string = ''
  @State regexTestResult: string = ''

  aboutToAppear(): void {
    this.load()
  }

  async load(): Promise<void> {
    this.loading = true
    try {
      // 确保内置规则已补齐（防止 EntryAbility 初始化时序问题导致页面为空）
      await DupRuleConfigDao.ensureBuiltinSeeded()
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

  onBackPress(): boolean {
    if (this.showEditor) {
      this.showEditor = false;
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      Column({ space: 8 }) {
        TopBar({ title: '勾选重复规则' })

        Text('选择「勾选重复」时应用的重复检测规则。内置规则为系统预设，自定义规则可灵活组合条件。')
          .fontSize(12).fontColor($r('app.color.text_hint'))
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
              Button('+ 新增').fontSize(12).height(30).backgroundColor($r('app.color.primary')).fontColor($r('app.color.text_on_primary'))
                .onClick(() => this.openAdd())
            }
            .width('100%').padding({ left: 4, top: 12, right: 4 })

            if (this.customRules.length === 0) {
              Text('暂无自定义规则').fontSize(12).fontColor($r('app.color.text_hint')).padding(8)
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
      .backgroundColor($r('app.color.bg_page'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.showEditor) {
        this.editorPanel()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ruleToggle(label: string, desc: string, isOn: boolean, onChange: (v: boolean) => void) {
    Row() {
      Column({ space: 2 }) {
        Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(desc).fontSize(11).fontColor($r('app.color.text_hint')).lineHeight(16)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((v: boolean) => onChange(v))
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  customCard(r: DupRuleConfig) {
    Column({ space: 6 }) {
      Row() {
        Column({ space: 2 }) {
          Text(r.ruleName).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(r.action === 'protect' ? '动作：保护(不勾选)' : '动作：勾选(重复)')
            .fontSize(11).fontColor(r.action === 'protect' ? $r('app.color.warning') : $r('app.color.primary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // F组 #19 自定义规则可停用开关
        Toggle({ type: ToggleType.Switch, isOn: r.enabled === 1 })
          .onChange((v: boolean) => this.toggleCustom(r, v))
      }
      .width('100%')

      Text(this.condSummary(r.conditions))
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 2 })

      // 操作按钮单独一行
      Row({ space: 6 }) {
        Blank()
        Button('编辑').fontSize(12).height(30).onClick(() => this.openEdit(r))
        Button('删除').fontSize(12).height(30).backgroundColor($r('app.color.danger')).fontColor($r('app.color.text_on_primary'))
          .onClick(() => this.deleteRule(r))
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_card'))
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
    for (const o of FIELD_CHOICES) {
      if (o.key === f) {
        return o.label
      }
    }
    return f
  }

  private opLabel(o: string): string {
    for (const p of OP_CHOICES) {
      if (p.key === o) {
        return p.label
      }
    }
    return o
  }

  private parseConds(json: string): EditCond[] {
    const result: EditCond[] = []
    if (!json || json.trim().length === 0) {
      return result
    }
    // F组 #18 兼容安卓新格式 {"field":"x","regex":"y"}
    const reNew: RegExp = /\{"field":"([^"]+)","regex":"([^"]*)"\}/g
    let m: RegExpExecArray | null = reNew.exec(json)
    while (m !== null) {
      result.push({ field: m[1], op: 'regex', value: m[2] })
      m = reNew.exec(json)
    }
    if (result.length > 0) {
      return result
    }
    // 旧格式 {"field":"x","op":"y","value":"z"}
    const re: RegExp = /\{"field":"([^"]+)","op":"([^"]+)","value":"([^"]*)"\}/g
    m = re.exec(json)
    while (m !== null) {
      result.push({ field: m[1], op: m[2], value: m[3] })
      m = re.exec(json)
    }
    return result
  }

  async toggleBuiltin(r: DupRuleConfig, v: boolean): Promise<void> {
    try {
      r.enabled = v ? 1 : 0
      await DupRuleConfigDao.updateEnabled(r.id, r.enabled)
      LogUtil.i('DupRuleSettings', `内置规则 ${r.ruleKey} -> ${r.enabled}`)
    } catch (e) {
      LogUtil.e('DupRuleSettings', `切换内置规则失败: ${(e as Error).message}`)
      ToastUtil.show('操作失败')
      r.enabled = v ? 0 : 1
    }
  }

  // F组 #19 切换自定义规则启停
  async toggleCustom(r: DupRuleConfig, v: boolean): Promise<void> {
    try {
      r.enabled = v ? 1 : 0
      await DupRuleConfigDao.updateEnabled(r.id, r.enabled)
      LogUtil.i('DupRuleSettings', `自定义规则 ${r.id} -> ${r.enabled}`)
    } catch (e) {
      LogUtil.e('DupRuleSettings', `切换自定义规则失败: ${(e as Error).message}`)
      ToastUtil.show('操作失败')
      r.enabled = v ? 0 : 1
    }
  }

  // ===================== 编辑器 =====================
  private openAdd(): void {
    this.editingId = 0
    this.editName = ''
    this.editDesc = ''
    this.editAction = 'check'
    this.editConds = [{ field: 'file_name', op: 'contains', value: '' }]
    // F组 #20 重置正则测试器
    this.regexPattern = ''
    this.regexTestInput = ''
    this.regexTestResult = ''
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
    // F组 #20 若已有正则条件，预填到测试器
    const regexCond: EditCond | undefined = this.editConds.find((c) => c.op === 'regex')
    this.regexPattern = regexCond ? regexCond.value : ''
    this.regexTestInput = ''
    this.regexTestResult = ''
    this.showEditor = true
  }

  // F组 #20 正则测试
  private testRegex(): void {
    if (this.regexPattern.trim().length === 0) {
      this.regexTestResult = '请先输入正则表达式'
      return
    }
    try {
      const re: RegExp = new RegExp(this.regexPattern)
      if (re.test(this.regexTestInput)) {
        this.regexTestResult = '✓ 匹配成功'
      } else {
        this.regexTestResult = '✗ 不匹配'
      }
    } catch (e) {
      this.regexTestResult = `✗ 正则非法: ${(e as Error).message}`
    }
  }

  async deleteRule(r: DupRuleConfig): Promise<void> {
    try {
      await DupRuleConfigDao.delete(r.id)
      ToastUtil.show('已删除自定义规则', 1500)
      await this.load()
    } catch (e) {
      LogUtil.e('DupRuleSettings', `删除规则失败: ${(e as Error).message}`)
      ToastUtil.show('删除失败')
    }
  }

  @Builder
  editorPanel() {
    Column() {
      Row() {
        Button('取消').onClick(() => { this.showEditor = false })
        Text(this.editingId === 0 ? '新增自定义规则' : '编辑自定义规则')
          .fontSize(16).fontWeight(FontWeight.Bold).margin({ left: 8 })
        Blank()
        Button('保存').backgroundColor($r('app.color.primary')).fontColor($r('app.color.text_on_primary'))
          .onClick(() => this.saveRule())
      }
      .width('100%').padding(12)
      .backgroundColor($r('app.color.bg_card'))

      Scroll() {
        Column({ space: 10 }) {
          Text('规则名称').fontSize(13).fontColor($r('app.color.text_secondary'))
          AppTextInput({ placeholder: '如：屏蔽某站点', text: this.editName, onChangeCallback: (v: string) => { this.editName = v } })

          Text('说明').fontSize(13).fontColor($r('app.color.text_secondary'))
          AppTextInput({ placeholder: '可选', text: this.editDesc, onChangeCallback: (v: string) => { this.editDesc = v } })

          Text('命中后动作').fontSize(13).fontColor($r('app.color.text_secondary'))
          Row({ space: 12 }) {
            this.actionBtn('勾选(标记重复)', 'check')
            this.actionBtn('保护(不勾选)', 'protect')
          }

          Row() {
            Text('条件（全部满足）').fontSize(13).fontColor($r('app.color.text_secondary'))
            Blank()
            Button('+ 条件').fontSize(12).height(30).backgroundColor($r('app.color.success')).fontColor($r('app.color.text_on_primary'))
              .onClick(() => {
                this.editConds.push({ field: 'file_name', op: 'contains', value: '' })
                this.editConds = [...this.editConds]
              })
          }
          .width('100%')

          ForEach(this.editConds, (c: EditCond, idx: number) => {
            this.condEditor(c, idx)
          }, (c: EditCond, idx: number) => idx.toString())

          // F组 #20 正则测试器
          Column({ space: 6 }) {
            Text('正则测试器').fontSize(13).fontColor($r('app.color.text_secondary'))
            Text('输入正则与测试文本，校验是否匹配（用于 op=正则匹配 的条件）')
              .fontSize(11).fontColor($r('app.color.text_hint'))
            AppTextInput({ placeholder: '正则表达式，如 \\d+', text: this.regexPattern, onChangeCallback: (v: string) => { this.regexPattern = v } })
            AppTextInput({ placeholder: '测试文本', text: this.regexTestInput, onChangeCallback: (v: string) => { this.regexTestInput = v } })
            if (this.regexTestResult.length > 0) {
              Text(this.regexTestResult)
                .fontSize(12)
                .fontColor(this.regexTestResult.startsWith('✓') ? $r('app.color.success') : $r('app.color.danger'))
            }
            Button('测试匹配')
              .fontSize(12).height(34).width('100%')
              .backgroundColor($r('app.color.primary')).fontColor($r('app.color.text_on_primary'))
              .onClick(() => this.testRegex())
          }
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.bg_light'))
          .borderRadius(8)
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('92%')
    .backgroundColor($r('app.color.bg_card'))
    .position({ x: 0, y: '8%' })
  }

  @Builder
  actionBtn(label: string, value: string) {
    Button(label)
      .fontSize(13)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.editAction === value ? $r('app.color.primary') : $r('app.color.divider'))
      .fontColor(this.editAction === value ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
      .onClick(() => { this.editAction = value })
  }

  @Builder
  condEditor(c: EditCond, idx: number) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text('如果').fontSize(12).fontWeight(FontWeight.Medium).alignSelf(ItemAlign.Center).fontColor($r('app.color.text_primary'))
        Select(FIELD_OPTIONS)
          .value(this.fieldLabel(c.field))
          .layoutWeight(1)
          .onSelect((i: number) => {
            c.field = FIELD_CHOICES[i].key
            this.editConds = [...this.editConds]
          })
        Button('删')
          .fontSize(12).height(28).width(40)
          .backgroundColor($r('app.color.danger')).fontColor($r('app.color.text_on_primary'))
          .enabled(this.editConds.length > 1)
          .onClick(() => {
            this.editConds.splice(idx, 1)
            this.editConds = [...this.editConds]
          })
      }
      .width('100%')

      Row({ space: 6 }) {
        Select(OP_OPTIONS)
          .value(this.opLabel(c.op))
          .layoutWeight(1)
          .onSelect((i: number) => {
            c.op = OP_CHOICES[i].key
            this.editConds = [...this.editConds]
          })
        AppTextInput({ placeholder: '值', text: c.value, expand: true, onChangeCallback: (v: string) => {
          c.value = v
          this.editConds = [...this.editConds]
        } })
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.bg_light'))
    .borderRadius(8)
  }

  private condsToJson(conds: EditCond[]): string {
    const items: EditCond[] = conds.filter((c) => c.value.trim().length > 0)
    return JSON.stringify(items)
  }

  async saveRule(): Promise<void> {
    if (this.editName.trim().length === 0) {
      ToastUtil.show('请填写规则名称', 1500)
      return
    }
    const valid: EditCond[] = this.editConds.filter((c) => c.value.trim().length > 0)
    if (valid.length === 0) {
      ToastUtil.show('请至少配置一个条件的值', 1500)
      return
    }
    try {
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
      ToastUtil.show('已保存', 1500)
      await this.load()
    } catch (e) {
      LogUtil.e('DupRuleSettings', `保存规则失败: ${(e as Error).message}`)
      ToastUtil.show(`保存失败: ${(e as Error).message}`)
    }
  }
}
