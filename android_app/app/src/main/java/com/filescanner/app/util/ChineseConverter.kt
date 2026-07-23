package com.filescanner.app.util

import com.github.houbb.opencc4j.util.ZhConverterUtil

/**
 * 繁体 → 简体 转换器（基于 opencc4j）。
 *
 * 用于文件名解析阶段：若解析到的书名/作者/进度/来源为繁体字，统一转换为简体后再入库，
 * 避免同一本书因繁简写法不同而无法识别为重复、或检索时命中不到。
 *
 * 性能：绝大多数文件名本身就是简体，先用 [ZhConverterUtil.isSimple]（HashSet 级字符判断，
 * 开销极小）快速判定，只有确实含繁体字的字符串才走 [ZhConverterUtil.toSimple] 转换，
 * 避免对 10w+ 文件逐一做重量级分词转换而拖慢扫描。
 */
object ChineseConverter {

    /** 将可能含繁体字的文本转换为简体；已是简体或空串则原样返回。任何异常都安全回退原文。 */
    fun toSimplified(text: String): String {
        if (text.isEmpty()) return text
        return try {
            if (ZhConverterUtil.isSimple(text)) text
            else ZhConverterUtil.toSimple(text)
        } catch (_: Throwable) {
            // 极端情况下（如字典加载异常）不影响主流程，返回原文
            text
        }
    }
}
