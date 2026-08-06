"""
批量处理鸿蒙应用商店送审截图（无黑边版本）：
- 目标尺寸：1080 x 1920 px（9:16 比例）
- 输入：C:/Users/a/Pictures/*.png
- 输出：C:/Users/a/Pictures/screenshots_harmony/
- 处理逻辑（保证零黑边）：
  先等比缩放使图片覆盖目标框（scale = max(TW/iw, TH/ih)），
  再居中裁剪到 1080x1920。crop 始终在原图范围内，不产生黑边。
"""

import os
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("需要安装 Pillow: pip install Pillow")
    sys.exit(1)

INPUT_DIR = Path("C:/Users/a/Pictures")
OUTPUT_DIR = INPUT_DIR / "screenshots_harmony"
TARGET_W = 1080
TARGET_H = 1920


def process_image(src_path: Path) -> str | None:
    try:
        img = Image.open(src_path).convert("RGB")
        iw, ih = img.size

        # 1) 等比放大/缩小，使图片完全覆盖目标框（取较大缩放比）
        scale = max(TARGET_W / iw, TARGET_H / ih)
        new_w = int(round(iw * scale))
        new_h = int(round(ih * scale))
        img = img.resize((new_w, new_h), Image.LANCZOS)

        # 2) 居中裁剪到目标尺寸（new_w/new_h 一定 >= 目标，crop 在范围内）
        left = (new_w - TARGET_W) // 2
        top = (new_h - TARGET_H) // 2
        img = img.crop((left, top, left + TARGET_W, top + TARGET_H))

        out_name = f"{src_path.stem}_{TARGET_W}x{TARGET_H}.jpg"
        out_path = OUTPUT_DIR / out_name
        img.save(out_path, "JPEG", quality=95)
        return out_name
    except Exception as e:
        print(f"  [ERROR] {src_path.name}: {e}")
        return None


def main():
    OUTPUT_DIR.mkdir(exist_ok=True)

    png_files = sorted(INPUT_DIR.glob("*.png"))
    if not png_files:
        print(f"{INPUT_DIR} 下没有 PNG 文件")
        return

    print(f"找到 {len(png_files)} 张 PNG")
    print(f"输出目录: {OUTPUT_DIR}")
    print(f"目标尺寸: {TARGET_W}x{TARGET_H} (9:16)")
    print("-" * 50)

    success = 0
    for p in png_files:
        result = process_image(p)
        if result:
            print(f"  OK: {p.name} -> {result}")
            success += 1

    print("-" * 50)
    print(f"完成: {success}/{len(png_files)} 张处理成功")


if __name__ == "__main__":
    main()
