import os
import shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter

WIDTH = 1080
HEIGHT = 1920

FONTS_DIR = "game/assets/fonts"
FONT_TITLE_PATH = os.path.join(FONTS_DIR, "RussoOne.ttf")
FONT_TEXT_PATH = os.path.join(FONTS_DIR, "Onest.ttf")

OUT_DIR = "Builds/RuStore"
RAW_DIR = "artifacts/store_raw_tall"
COIN_PATH = "game/assets/models/treasures/icon_coin.png"
ARTIFACT_DIR = r"C:\Users\isaev\.gemini\antigravity\brain\4401acc1-9a05-4b61-a610-ea65f6436c1b\cards"

os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs("artifacts/rustore_cards", exist_ok=True)
os.makedirs(ARTIFACT_DIR, exist_ok=True)

def get_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()

def create_gradient_bg(width, height, top_color, bottom_color, accent_color=None, accent_pos=(0.5, 0.45), accent_radius=680):
    base = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(base)
    
    r1, g1, b1 = top_color
    r2, g2, b2 = bottom_color
    for y in range(height):
        t = y / float(height - 1)
        t_smooth = t * t * (3 - 2 * t)
        r = int(r1 + (r2 - r1) * t_smooth)
        g = int(g1 + (g2 - g1) * t_smooth)
        b = int(b1 + (b2 - b1) * t_smooth)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))
        
    if accent_color:
        glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow)
        ax, ay = int(width * accent_pos[0]), int(height * accent_pos[1])
        ar, ag, ab = accent_color
        
        steps = 45
        for i in range(steps, 0, -1):
            cur_rad = int(accent_radius * (i / float(steps)))
            alpha = int(52 * (1.0 - (i / float(steps)) ** 1.4))
            glow_draw.ellipse(
                [(ax - cur_rad, ay - cur_rad), (ax + cur_rad, ay + cur_rad)],
                fill=(ar, ag, ab, alpha)
            )
        glow = glow.filter(ImageFilter.GaussianBlur(radius=35))
        base = Image.alpha_composite(base, glow)

    vignette = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    v_draw = ImageDraw.Draw(vignette)
    for y in range(height):
        dy = min(y, height - 1 - y)
        if dy < 220:
            v_alpha = int(90 * (1.0 - dy / 220.0))
            v_draw.line([(0, y), (width, y)], fill=(0, 0, 0, v_alpha))
    base = Image.alpha_composite(base, vignette)

    return base

def create_rounded_mask(width, height, radius):
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (width - 1, height - 1)], radius=radius, fill=255)
    return mask

def create_phone_mockup(screen_img_path, screen_w=640, screen_h=1386, bezel_side=12, bezel_top=16, bezel_bottom=16, radius=42):
    phone_w = screen_w + bezel_side * 2
    phone_h = screen_h + bezel_top + bezel_bottom
    
    phone = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    p_draw = ImageDraw.Draw(phone)
    
    # Outer sleek titanium chassis
    p_draw.rounded_rectangle(
        [(0, 0), (phone_w - 1, phone_h - 1)],
        radius=radius,
        fill=(16, 20, 26, 255),
        outline=(80, 92, 110, 255),
        width=2
    )
    
    # Subtle speaker slit in top bezel (outside screen, never covers UI!)
    speaker_w = 64
    speaker_h = 4
    speaker_x = (phone_w - speaker_w) // 2
    speaker_y = 6
    p_draw.rounded_rectangle(
        [(speaker_x, speaker_y), (speaker_x + speaker_w, speaker_y + speaker_h)],
        radius=2,
        fill=(35, 42, 54, 255)
    )
    
    # Screen content: 100% UNTOUCHED, no notches or cuts inside!
    if os.path.exists(screen_img_path):
        screen_src = Image.open(screen_img_path).convert("RGBA")
        screen_resized = screen_src.resize((screen_w, screen_h), Image.LANCZOS)
    else:
        screen_resized = Image.new("RGBA", (screen_w, screen_h), (30, 40, 50, 255))
        
    screen_mask = create_rounded_mask(screen_w, screen_h, radius=radius - 8)
    phone.paste(screen_resized, (bezel_side, bezel_top), screen_mask)
    
    # Inner border line around screen
    inner_draw = ImageDraw.Draw(phone)
    inner_draw.rounded_rectangle(
        [(bezel_side, bezel_top), (bezel_side + screen_w - 1, bezel_top + screen_h - 1)],
        radius=radius - 8,
        outline=(255, 255, 255, 28),
        width=1
    )

    # Multi-stage realistic drop shadow
    pad = 55
    shadow_w = phone_w + pad * 2
    shadow_h = phone_h + pad * 2
    shadow = Image.new("RGBA", (shadow_w, shadow_h), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    
    # Ambient soft shadow
    s_draw.rounded_rectangle(
        [(pad, pad + 18), (pad + phone_w, pad + phone_h + 18)],
        radius=radius,
        fill=(0, 0, 0, 115)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=26))
    
    # Contact shadow
    contact = Image.new("RGBA", (shadow_w, shadow_h), (0, 0, 0, 0))
    c_draw = ImageDraw.Draw(contact)
    c_draw.rounded_rectangle(
        [(pad, pad + 8), (pad + phone_w, pad + phone_h + 8)],
        radius=radius,
        fill=(0, 0, 0, 135)
    )
    contact = contact.filter(ImageFilter.GaussianBlur(radius=8))
    shadow = Image.alpha_composite(shadow, contact)
    
    phone_with_shadow = Image.new("RGBA", (shadow_w, shadow_h), (0, 0, 0, 0))
    phone_with_shadow.paste(shadow, (0, 0))
    phone_with_shadow.paste(phone, (pad, pad), phone)
    
    return phone_with_shadow, pad

def draw_pill_badge(draw, center_x, center_y, text, font, border_color, fill_color=(15, 23, 42, 225), text_color=(255, 255, 255)):
    bbox = font.getbbox(text)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    
    pad_x = 22
    pad_y = 9
    pill_w = tw + pad_x * 2
    pill_h = th + pad_y * 2
    
    x1 = int(center_x - pill_w / 2)
    y1 = int(center_y - pill_h / 2)
    x2 = x1 + pill_w
    y2 = y1 + pill_h
    
    radius = pill_h // 2
    draw.rounded_rectangle(
        [(x1, y1), (x2, y2)],
        radius=radius,
        fill=fill_color,
        outline=border_color,
        width=2
    )
    
    tx = x1 + pad_x - bbox[0]
    ty = y1 + pad_y - bbox[1]
    draw.text((tx, ty), text, font=font, fill=text_color)
    return x1, y1, x2, y2

def draw_header_section(card, badge_text, badge_color, title_lines, subtitle_text, feature_chips):
    font_badge = get_font(FONT_TITLE_PATH, 20)
    font_title = get_font(FONT_TITLE_PATH, 58)
    font_sub = get_font(FONT_TEXT_PATH, 27)
    font_chip = get_font(FONT_TITLE_PATH, 21)
    
    header_layer = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(header_layer)
    
    # 1. Top category badge
    draw_pill_badge(
        draw,
        center_x=WIDTH // 2,
        center_y=72,
        text=badge_text,
        font=font_badge,
        border_color=badge_color,
        fill_color=(12, 17, 28, 235),
        text_color=badge_color
    )
    
    # 2. Main Title (1 or 2 lines)
    start_y = 120
    line_spacing = 68
    for i, line in enumerate(title_lines):
        line_y = start_y + i * line_spacing
        bbox = font_title.getbbox(line)
        tw = bbox[2] - bbox[0]
        tx = (WIDTH - tw) // 2 - bbox[0]
        
        # Soft shadow
        draw.text((tx + 2, line_y + 3), line, font=font_title, fill=(0, 0, 0, 190))
        draw.text((tx, line_y), line, font=font_title, fill=(255, 255, 255, 255))
        
    # 3. Subtitle
    sub_y = start_y + len(title_lines) * line_spacing + 10
    bbox_sub = font_sub.getbbox(subtitle_text)
    sub_w = bbox_sub[2] - bbox_sub[0]
    sx = (WIDTH - sub_w) // 2 - bbox_sub[0]
    
    draw.text((sx + 1, sub_y + 2), subtitle_text, font=font_sub, fill=(0, 0, 0, 170))
    draw.text((sx, sub_y), subtitle_text, font=font_sub, fill=(215, 226, 240, 255))
    
    # 4. Feature Chips row (centered under subtitle, above phone)
    chips_y = sub_y + 48
    
    # Calculate widths for all chips in the row
    chip_widths = []
    chip_h = 42
    for chip in feature_chips:
        text = chip["text"]
        has_icon = chip.get("icon_path") and os.path.exists(chip["icon_path"])
        icon_w = 26 if has_icon else (font_chip.getbbox(chip.get("icon", ""))[2] + 6 if chip.get("icon") else 0)
        t_w = font_chip.getbbox(text)[2] - font_chip.getbbox(text)[0]
        w = t_w + icon_w + 36
        chip_widths.append(w)
        
    gap = 18
    total_chips_w = sum(chip_widths) + gap * (len(chip_widths) - 1)
    cur_x = (WIDTH - total_chips_w) // 2
    
    for i, chip in enumerate(feature_chips):
        w = chip_widths[i]
        accent = chip.get("accent", badge_color)
        
        # Shadow
        draw.rounded_rectangle(
            [(cur_x + 1, chips_y + 3), (cur_x + w + 1, chips_y + chip_h + 3)],
            radius=chip_h // 2,
            fill=(0, 0, 0, 100)
        )
        # Pill
        draw.rounded_rectangle(
            [(cur_x, chips_y), (cur_x + w, chips_y + chip_h)],
            radius=chip_h // 2,
            fill=(14, 20, 32, 240),
            outline=accent,
            width=2
        )
        
        # Draw icon and text
        inner_x = cur_x + 16
        if chip.get("icon_path") and os.path.exists(chip["icon_path"]):
            c_icon = Image.open(chip["icon_path"]).convert("RGBA")
            c_icon = c_icon.resize((24, 24), Image.LANCZOS)
            header_layer.paste(c_icon, (inner_x, chips_y + (chip_h - 24) // 2), c_icon)
            inner_x += 28
        elif chip.get("icon"):
            draw.text((inner_x, chips_y + (chip_h - font_chip.getbbox(chip["icon"])[3]) // 2 - 2), chip["icon"], font=font_chip, fill=accent)
            inner_x += font_chip.getbbox(chip["icon"])[2] + 6
            
        t_box = font_chip.getbbox(chip["text"])
        t_y = chips_y + (chip_h - (t_box[3] - t_box[1])) // 2 - t_box[1]
        draw.text((inner_x, t_y), chip["text"], font=font_chip, fill=(255, 255, 255, 255))
        
        cur_x += w + gap

    return Image.alpha_composite(card, header_layer)

# ========================================================
# CARD 1: Core Mechanics - ВОСХОЖДЕНИЕ НА ОДНОМ КРЮКЕ
# ========================================================
def generate_card_1():
    print("Generating Tall Card 1: Hook & Core Gameplay...")
    bg = create_gradient_bg(
        WIDTH, HEIGHT,
        top_color=(10, 24, 32),
        bottom_color=(18, 41, 46),
        accent_color=(34, 197, 94),
        accent_pos=(0.5, 0.52),
        accent_radius=680
    )
    
    phone, pad = create_phone_mockup(
        os.path.join(RAW_DIR, "tall_forest.png"),
        screen_w=640, screen_h=1386
    )
    phone_x = (WIDTH - phone.width) // 2
    phone_y = 430 - pad
    bg.paste(phone, (phone_x, phone_y), phone)
    
    card = draw_header_section(
        bg,
        badge_text="• АРКАДНЫЙ СИМУЛЯТОР АЛЬПИНИЗМА •",
        badge_color=(56, 189, 248),
        title_lines=["ВОСХОЖДЕНИЕ", "НА ОДНОМ КРЮКЕ"],
        subtitle_text="Цепляйся за выступы, раскачивайся и покоряй гору",
        feature_chips=[
            {"icon": "⚡", "text": "В ОДНО КАСАНИЕ", "accent": (245, 158, 11)},
            {"icon": "🪝", "text": "ФИЗИКА КАНАТА", "accent": (56, 189, 248)}
        ]
    )
    
    out_path = os.path.join(OUT_DIR, "rustore_card_01_hook.png")
    card.convert("RGB").save(out_path, quality=95)
    card.convert("RGB").save("artifacts/rustore_cards/card_01_hook.png", quality=95)
    card.convert("RGB").save(os.path.join(ARTIFACT_DIR, "rustore_card_01_hook.png"), quality=95)
    print(f"Card 1 saved to {out_path}")

# ========================================================
# CARD 2: Expeditions & Biomes - 3 ОПАСНЫХ БИОМА
# ========================================================
def generate_card_2():
    print("Generating Tall Card 2: 3 Biomes & Expeditions...")
    bg = create_gradient_bg(
        WIDTH, HEIGHT,
        top_color=(12, 22, 44),
        bottom_color=(18, 38, 62),
        accent_color=(6, 182, 212),
        accent_pos=(0.5, 0.52),
        accent_radius=680
    )
    
    phone_snow, pad_snow = create_phone_mockup(
        os.path.join(RAW_DIR, "tall_snow.png"),
        screen_w=640, screen_h=1386
    )
    phone_x = (WIDTH - phone_snow.width) // 2
    phone_y = 430 - pad_snow
    bg.paste(phone_snow, (phone_x, phone_y), phone_snow)
    
    card = draw_header_section(
        bg,
        badge_text="• 3 ЭКСПЕДИЦИИ И МАРШРУТЫ •",
        badge_color=(6, 182, 212),
        title_lines=["НЕПРЕДСКАЗУЕМЫЕ", "СКЛОНЫ И БИОМЫ"],
        subtitle_text="Хвойные скалы, раскаленный каньон и ледяные пики",
        feature_chips=[
            {"icon": "🌲", "text": "ЛЕС", "accent": (34, 197, 94)},
            {"icon": "🏜️", "text": "КАНЬОН", "accent": (245, 158, 11)},
            {"icon": "❄️", "text": "ЛЕДНИК", "accent": (6, 182, 212)}
        ]
    )
    
    out_path = os.path.join(OUT_DIR, "rustore_card_02_biomes.png")
    card.convert("RGB").save(out_path, quality=95)
    card.convert("RGB").save("artifacts/rustore_cards/card_02_biomes.png", quality=95)
    card.convert("RGB").save(os.path.join(ARTIFACT_DIR, "rustore_card_02_biomes.png"), quality=95)
    print(f"Card 2 saved to {out_path}")

# ========================================================
# CARD 3: Workshop & Upgrades - ПРОКАЧКА СНАРЯЖЕНИЯ
# ========================================================
def generate_card_3():
    print("Generating Tall Card 3: Workshop & Upgrades...")
    bg = create_gradient_bg(
        WIDTH, HEIGHT,
        top_color=(24, 18, 30),
        bottom_color=(38, 28, 42),
        accent_color=(234, 179, 8),
        accent_pos=(0.5, 0.52),
        accent_radius=680
    )
    
    phone, pad = create_phone_mockup(
        os.path.join(RAW_DIR, "tall_workshop.png"),
        screen_w=640, screen_h=1386
    )
    phone_x = (WIDTH - phone.width) // 2
    phone_y = 430 - pad
    bg.paste(phone, (phone_x, phone_y), phone)
    
    card = draw_header_section(
        bg,
        badge_text="• МАСТЕРСКАЯ И ЭКИПИРОВКА •",
        badge_color=(234, 179, 8),
        title_lines=["ПРОКАЧИВАЙ", "СВОЁ СНАРЯЖЕНИЕ"],
        subtitle_text="Укрепляй тросы, куй новые крюки и собирай реликвии",
        feature_chips=[
            {"icon_path": COIN_PATH, "text": "МОНЕТЫ И НАХОДКИ", "accent": (234, 179, 8)},
            {"icon": "⚙️", "text": "8 ВЕТОК ПРОКАЧКИ", "accent": (245, 158, 11)}
        ]
    )
    
    out_path = os.path.join(OUT_DIR, "rustore_card_03_workshop.png")
    card.convert("RGB").save(out_path, quality=95)
    card.convert("RGB").save("artifacts/rustore_cards/card_03_workshop.png", quality=95)
    card.convert("RGB").save(os.path.join(ARTIFACT_DIR, "rustore_card_03_workshop.png"), quality=95)
    print(f"Card 3 saved to {out_path}")

# ========================================================
# CARD 4: Summit Challenge - ПОКОРИ ВЕРШИНУ ГОРЫ (Desert Canyon)
# ========================================================
def generate_card_4():
    print("Generating Tall Card 4: Summit Challenge (Desert Canyon)...")
    bg = create_gradient_bg(
        WIDTH, HEIGHT,
        top_color=(28, 18, 16),
        bottom_color=(46, 26, 24),
        accent_color=(249, 115, 22),
        accent_pos=(0.5, 0.52),
        accent_radius=680
    )
    
    phone, pad = create_phone_mockup(
        os.path.join(RAW_DIR, "tall_desert.png"),
        screen_w=640, screen_h=1386
    )
    phone_x = (WIDTH - phone.width) // 2
    phone_y = 430 - pad
    bg.paste(phone, (phone_x, phone_y), phone)
    
    card = draw_header_section(
        bg,
        badge_text="• ИСПЫТАНИЕ ВЫСОТОЙ •",
        badge_color=(249, 115, 22),
        title_lines=["ПОКОРИ", "ВЕРШИНУ ГОРЫ"],
        subtitle_text="Точный расчёт каждого броска на пути к вершине",
        feature_chips=[
            {"icon": "🧗", "text": "ОПАСНЫЕ УСТУПЫ", "accent": (249, 115, 22)},
            {"icon": "🏆", "text": "ТРИУМФ ВОСХОЖДЕНИЯ", "accent": (234, 179, 8)}
        ]
    )
    
    out_path = os.path.join(OUT_DIR, "rustore_card_04_summit.png")
    card.convert("RGB").save(out_path, quality=95)
    card.convert("RGB").save("artifacts/rustore_cards/card_04_summit.png", quality=95)
    card.convert("RGB").save(os.path.join(ARTIFACT_DIR, "rustore_card_04_summit.png"), quality=95)
    print(f"Card 4 saved to {out_path}")

def update_showcase_banner():
    card_names = [
        "rustore_card_01_hook.png",
        "rustore_card_02_biomes.png",
        "rustore_card_03_workshop.png",
        "rustore_card_04_summit.png"
    ]
    loaded_imgs = [Image.open(os.path.join(OUT_DIR, name)) for name in card_names]
    
    thumb_w = 480
    thumb_h = int(thumb_w * 1920 / 1080)
    gap = 30
    pad = 40
    banner_w = pad * 2 + thumb_w * 4 + gap * 3
    banner_h = pad * 2 + thumb_h

    banner = Image.new("RGB", (banner_w, banner_h), (11, 15, 23))
    for i, im in enumerate(loaded_imgs):
        thumb = im.resize((thumb_w, thumb_h), Image.LANCZOS)
        x = pad + i * (thumb_w + gap)
        y = pad
        banner.paste(thumb, (x, y))

    showcase_path = os.path.join(ARTIFACT_DIR, "showcase_4in1.png")
    banner.save(showcase_path, quality=94)
    banner.save(os.path.join(OUT_DIR, "showcase_4in1.png"), quality=94)
    print(f"Showcase banner updated: {showcase_path}")

if __name__ == "__main__":
    generate_card_1()
    generate_card_2()
    generate_card_3()
    generate_card_4()
    update_showcase_banner()
    print("ALL 4 TALL POLISHED CARDS GENERATED!")
