import io
p = r'd:/user/project/批量文件清理和文件内容识别/txt文件清理-单工程清理/harmony_app/entry/src/main/ets/pages/LibraryList.ets'
a = io.open(p, encoding='utf-8').read().splitlines()
# 307行(idx306)=.width, 308行(idx307)=.height, 309行(idx308)= } // 闭合 Column
# 删除 307/308，把 309 改为闭合 else
del a[306]
del a[306]  # 原来的 308 现在移到 306 位置
a[306] = "      } // 闭合 else(runs.length===0)"
io.open(p, 'w', encoding='utf-8').write('\n'.join(a) + '\n')
print('done, lines', len(a))
