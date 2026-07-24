package com.filescanner.app.util

import com.github.houbb.opencc4j.util.ZhConverterUtil
import net.sourceforge.pinyin4j.PinyinHelper
import net.sourceforge.pinyin4j.format.HanyuPinyinOutputFormat
import net.sourceforge.pinyin4j.format.HanyuPinyinToneType
import net.sourceforge.pinyin4j.format.HanyuPinyinVCharType
import net.sourceforge.pinyin4j.format.exception.BadHanyuPinyinOutputFormatCombination

/**
 * 简体/拼音 转换工具。
 *
 * 用于文件名解析阶段：
 * - 繁体→简体：避免同一本书因繁简写法不同而无法识别重复；
 * - 中文→拼音：搜索时可输入拼音/首字母（如 dpcq）命中「斗破苍穹」。
 *
 * 拼音格式："全拼|首字母"（如 "dou po cang qiong|dpcq"），
 * 一条 LIKE 查询同时覆盖片段拼音与首字母匹配。
 *
 * 底层使用 pinyin4j（Maven Central），无需 JitPack。
 */
object ChineseConverter {

    private val pinyinFormat = HanyuPinyinOutputFormat().apply {
        toneType = HanyuPinyinToneType.WITHOUT_TONE
        vCharType = HanyuPinyinVCharType.WITH_V
    }

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

    /**
     * 生成拼音搜索字符串，格式 "全拼|首字母"。
     * 例："斗破苍穹" → "dou po cang qiong|dpcq"
     *
     * 空串或纯非中文文本返回空串，避免给搜索增加无意义的噪声列匹配。
     * 异常安全回退空串。
     */
    fun toPinyin(text: String): String {
        if (text.isBlank()) return ""
        return try {
            val full = toPinyinFull(text)
            if (full.isBlank()) return ""

            val initials = StringBuilder()
            for (ch in text) {
                if (isChinese(ch)) {
                    val py = pinyinForChar(ch)
                    if (py.isNotEmpty()) initials.append(py[0])
                }
            }
            if (initials.isEmpty()) return ""
            "$full|$initials"
        } catch (_: Throwable) {
            ""
        }
    }

    private fun toPinyinFull(text: String): String {
        val sb = StringBuilder()
        for (ch in text) {
            if (isChinese(ch)) {
                val py = pinyinForChar(ch)
                if (py.isNotEmpty()) {
                    if (sb.isNotEmpty()) sb.append(' ')
                    sb.append(py)
                }
            } else if (ch.isWhitespace()) {
                // skip whitespace in original text
            } else {
                if (sb.isNotEmpty()) sb.append(' ')
                sb.append(ch)
            }
        }
        return sb.toString()
    }

    private fun pinyinForChar(ch: Char): String {
        return try {
            val arr = PinyinHelper.toHanyuPinyinStringArray(ch, pinyinFormat)
            if (arr != null && arr.isNotEmpty()) arr[0] else ""
        } catch (_: BadHanyuPinyinOutputFormatCombination) {
            ""
        }
    }

    private fun isChinese(ch: Char): Boolean {
        return ch.code in 0x4E00..0x9FFF || ch.code in 0x3400..0x4DBF
    }
}
