@Entry
@Component
struct Help {
  build() {
    Column() {
      Text('使用帮助')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 24, bottom: 16 })
        .fontColor($r('app.color.text_primary'))

      Scroll() {
        Column({ space: 14 }) {
          this.section('1. 配置扫描目录',
            '在「扫描配置」中新建配置并选择要扫描的文件夹（通过系统文件选择器授权）。可设置文件类型、最小体积、是否递归子目录、是否精确哈希比对。')
          this.section('2. 开始扫描',
            '在文库列表点击「新建扫描」，选择目录后开始。扫描会遍历文件、按文件名解析出书名/作者/进度/来源，并实时写入本地数据库。')
          this.section('3. 浏览与筛选',
            '进入文库后可按「列表 / 合集」查看文件。合集按书名分组，便于发现重复。支持按书名/作者/文件名搜索，以及按时间/名称/大小排序。')
          this.section('4. 标记重复（一键勾选待删）',
            '在文库页或一键清理页点击「标记重复」，系统按五则规则（完全相等、纯数字进度、中文进度/完结、最大文件、完结+番外）自动勾选应删除的重复文件。')
          this.section('5. 删除文件',
            '勾选待删文件后进入删除确认，确认即删除物理文件与数据库记录。删除前建议先导出清单备份。')
          this.section('6. 关键词替换',
            '可配置「扫描阶段」与「解析阶段」的替换规则，扫描时自动对文件名或解析结果做字面量替换（如去除站点水印）。')
          this.section('7. 数据说明',
            '本应用纯本地运行，所有数据保存在应用私有目录，不上传任何服务器。删除文库仅清除数据库记录，不会删除原文件夹。')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  section(title: string, body: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary'))
      Text(body)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(20)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
