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
            '在文库列表点击「新建扫描」，选择目录后开始。扫描会遍历文件、按文件名解析出书名/作者/进度/来源，并实时写入本地数据库。文件名解析已能正确处理作者名的修订后缀，例如「作者：Nnnr（【修】山海镜花 融共同人）」会提取作者为 Nnnr，并正确识别来源、进度、书名。')
          this.section('3. 浏览与筛选',
            '进入文库后可按「列表 / 合集」查看文件。合集按书名分组，便于发现重复。在合集视图中，每个合集的汇总卡片标题下会实时显示该合集「已勾选 X 个」，方便确认待删项的数量。支持按书名/作者/文件名搜索，以及按时间/名称/大小排序。')
          this.section('4. 勾选重复（一键勾选待删）',
            '在文库页或一键清理页点击「勾选重复」，系统按五则规则（完全相等、纯数字进度、中文进度/完结、最大文件、完结+番外）自动勾选应删除的重复文件。勾选后，列表模式下已勾选文件自动排到最前面，合集模式下含已勾选项的合集排到最前面，方便快速确认。\n\n以上五则规则可在「设置」页的「勾选重复规则」中单独开启或关闭（默认全部启用）。你可以只启用想用的规则，关闭的规则不参与去重判断。')
          this.section('5. 删除文件',
            '勾选待删文件后进入删除确认，确认即删除物理文件与数据库记录。删除前建议先导出清单备份。')
          this.section('6. 设置',
            '"关键词替换"：可配置「扫描阶段」与「解析阶段」的替换规则，扫描时自动对文件名或解析结果做字面量替换（如去除站点水印）。\n\n"勾选重复规则"：在设置页可分别开关六条去重规则（默认全部启用），关闭的规则不参与「勾选重复」和删除的去重判断。')
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
