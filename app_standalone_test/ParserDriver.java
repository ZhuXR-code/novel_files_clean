import com.filescanner.app.util.Parser;
import com.filescanner.app.util.ParsedName;

public class ParserDriver {
    static int pass = 0;
    static int fail = 0;

    static void check(String name, String actual, String expected) {
        if (expected == null ? actual == null : expected.equals(actual)) {
            pass++;
            System.out.println("  [PASS] " + name + " = '" + actual + "'");
        } else {
            fail++;
            System.out.println("  [FAIL] " + name + " : expected '" + expected + "' but got '" + actual + "'");
        }
    }

    static void run(String fname) {
        ParsedName r = Parser.INSTANCE.parseFileName(fname);
        System.out.println("IN : " + fname);
        System.out.println("OUT: title='" + r.getTitle() + "' | author='" + r.getAuthor()
                + "' | progress='" + r.getProgress() + "' | source='" + r.getSource() + "'");
    }

    public static void main(String[] args) {
        System.out.println("==== 实际解析输出 ====");
        String[] cases = {
            "《都市奇缘》作者：张三（更50）.txt",
            "《都市奇缘》作者：张三（更50）精校.txt",
            "《深海》123.txt",
            "【晋江】《名》作者：王五.txt",
            "仙侠世界 李四 更100.txt",
            "《诛仙》作者：萧鼎 [起点] (更200).txt",
            "《庆余年》作者：猫腻【纵横】（更300）.txt",
            "说明.txt",
            "README.txt",
            "12345.txt",
            "[废文]《默读》作者：priest（完结）.txt",
            "《天官赐福》作者：墨香铜臭 番外合集.txt",
            "诡秘之主 爱潜水的乌贼 更1500.txt",
            "《全职高手》作者：蝴蝶蓝.txt",
            "《无作者》.txt",
            "作者：李四《书名》.txt"
        };
        for (String c : cases) run(c);

        System.out.println("\n==== 无歧义断言 ====");
        ParsedName r;
        r = Parser.INSTANCE.parseFileName("《都市奇缘》作者：张三（更50）.txt");
        check("标准-书名", r.getTitle(), "都市奇缘");
        check("标准-作者(清洗括号)", r.getAuthor(), "张三");

        r = Parser.INSTANCE.parseFileName("《深海》123.txt");
        check("无作者-书名", r.getTitle(), "深海");
        check("无作者-作者空", r.getAuthor(), "");

        r = Parser.INSTANCE.parseFileName("【晋江】《名》作者：王五.txt");
        check("来源-书名", r.getTitle(), "名");
        check("来源-作者", r.getAuthor(), "王五");
        check("来源-来源含晋江", r.getSource().contains("晋江") ? r.getSource() : "", "晋江");

        r = Parser.INSTANCE.parseFileName("说明.txt");
        check("关键词屏蔽-空", r.getTitle(), "");

        r = Parser.INSTANCE.parseFileName("README.txt");
        check("README屏蔽-空", r.getTitle(), "");

        r = Parser.INSTANCE.parseFileName("12345.txt");
        check("纯数字-空", r.getTitle(), "");

        System.out.println("\n==== 修复验证：圆括号进度/状态提取（对齐 PC 端） ====");
        r = Parser.INSTANCE.parseFileName("《都市奇缘》作者：张三（更50）.txt");
        check("（更50）-进度", r.getProgress(), "50");

        r = Parser.INSTANCE.parseFileName("《庆余年》作者：猫腻【纵横】（更300）.txt");
        check("（更300）-进度", r.getProgress(), "300");
        check("（更300）-来源保持纵横", r.getSource(), "纵横");

        r = Parser.INSTANCE.parseFileName("[废文]《默读》作者：priest（完结）.txt");
        check("（完结）-状态", r.getProgress(), "完结");

        r = Parser.INSTANCE.parseFileName("《诛仙》作者：萧鼎 [起点] (更200).txt");
        check("(更200)-半角进度", r.getProgress(), "200");
        check("[起点]-来源", r.getSource(), "起点");

        System.out.println("\n==== 结果 (" + pass + " pass / " + fail + " fail) ====");
        if (fail > 0) System.exit(1);
    }
}
