/**
 * 统一输入框组件。
 * 修复上架检测反馈：TextInput 未显式设置字体色/背景色时，
 * 系统默认文字与卡片背景对比度不足（浅色 1.11 / 深色 1.34），
 * 不符合 HarmonyOS 色彩对比度规范。
 * 此处统一设定：文字=text_primary、占位符=text_secondary、背景=bg_card，
 * 保证浅色与深色模式下对比度均 >= 4.5:1。
 */
@Component
export struct AppTextInput {
  @Prop text: string = ''
  @Prop placeholder: string = ''
  @Prop inputType: InputType = InputType.Normal
  @Prop expand: boolean = false
  @Prop inputHeight: number = 40
  @Prop widthValue: number | string = '100%'
  @Prop fontSizeVal: number = 14
  controller: TextInputController = new TextInputController()
  onChangeCallback?: (value: string) => void

  build() {
    TextInput({ text: this.text, placeholder: this.placeholder, controller: this.controller })
      .type(this.inputType)
      .width(this.widthValue)
      .height(this.inputHeight)
      .layoutWeight(this.expand ? 1 : undefined)
      .fontSize(this.fontSizeVal)
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_secondary'))
      .backgroundColor($r('app.color.bg_card'))
      .border({ width: 1, color: $r('app.color.divider') })
      .borderRadius(8)
      .padding({ left: 12, right: 12 })
      .onChange((value: string) => {
        if (this.onChangeCallback) {
          this.onChangeCallback(value)
        }
      })
  }
}
