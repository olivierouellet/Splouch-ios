"""Builds the App Store marketing art in Screenshots/Marketing/ from the captures
scripts/screenshots.sh leaves in Screenshots/<device>/<lang>/dark/:

  <listing>/screenshots/<size>/N-<screen>.png   a caption over the capture in a device frame
  <listing>/artwork/header-<W>x<H>.png          product page header: the app alone, no text
  <listing>/artwork/search-<W>x<H>.png          search results: what the app is, at a glance

  uv run --with pillow python scripts/store-art.py

Sizes are App Store Connect's (screenshot specifications, asset best practices).
iPhone Duo has no simulator, so its two displays frame the iPhone captures. No URL,
price or platform name in the art, which App Store asks for. Every image is RGB:
App Store Connect refuses an alpha channel.
"""

import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / "Screenshots"
OUT = SHOTS / "Marketing"
ICON = ROOT / "App/AppIcon.icon/Assets/splouch-icon-s-cutout 2.png"
FONT = "/System/Library/Fonts/SFNS.ttf"

LISTINGS = {"en-CA": "en", "fr-CA": "fr", "es-MX": "es"}
SCREENS = ["picker", "scoreboard", "results", "schedule"]

# Canvas size, capture folder, device kind.
SIZES = {
    "iphone-6.3": ((1206, 2622), "iphone-6.3", "phone"),
    "iphone-6.9": ((1320, 2868), "iphone-6.9", "phone"),
    "iphone-duo-outer": ((1398, 2034), "iphone-6.3", "phone"),
    "iphone-duo-inner": ((2007, 2853), "iphone-6.9", "phone"),
    "ipad-13": ((2064, 2752), "ipad-13", "tablet"),
}
HEADERS = [(5244, 2950), (3840, 1646)]
SEARCH = [(5244, 2950), (3840, 2560), (1920, 1280)]

# The icon's own blues, and the scoreboard's yellow.
NAVY_TOP = (6, 18, 46)
NAVY_BOTTOM = (11, 58, 140)
GLOW = (43, 196, 234)
YELLOW = (255, 214, 10)
SUBTLE = (190, 222, 255)

CAPTIONS = {
    "en": {
        "picker": ("Find your meet", "Online, or on the pool's own wifi"),
        "scoreboard": ("The scoreboard, in your hand", "Every lane, live from the timing console"),
        "results": ("Every result as it lands", "Times, places and gaps to seed"),
        "schedule": ("Know when your swimmer is up", "Start lists, filters and heat alerts"),
        "search": "The pool's scoreboard, live on your phone",
    },
    "fr": {
        "picker": ("Trouvez votre compétition", "En ligne ou sur le wifi de la piscine"),
        "scoreboard": ("Le tableau dans votre main", "Chaque couloir, en direct de la console"),
        "results": ("Chaque résultat, dès l'arrivée", "Temps, places et écarts à l'inscription"),
        "schedule": ("Sachez quand votre nageur plonge", "Listes de départ, filtres et alertes"),
        "search": "Le tableau de la piscine, en direct sur votre téléphone",
    },
    "es": {
        "picker": ("Encuentra tu competencia", "En línea o en el wifi de la alberca"),
        "scoreboard": ("El marcador en tu mano", "Cada carril, en vivo desde la consola"),
        "results": ("Cada resultado al instante", "Tiempos, lugares y diferencias"),
        "schedule": ("Sabe cuándo le toca a tu nadador", "Listas de salida, filtros y avisos"),
        "search": "El marcador de la alberca, en vivo en tu teléfono",
    },
}


def font(size, weight):
    f = ImageFont.truetype(FONT, int(size))
    f.set_variation_by_axes([100, min(96, max(17, size / 4)), 400, weight])
    return f


def background(w, h, glow_at=(0.5, 0.62), glow_size=0.9):
    """Navy to the icon's blue, top to bottom, with a cyan glow behind the device."""
    grad = Image.linear_gradient("L").resize((w, h))
    bg = Image.composite(Image.new("RGB", (w, h), NAVY_BOTTOM), Image.new("RGB", (w, h), NAVY_TOP), grad)
    r = max(w, h) * glow_size / 2
    cx, cy = w * glow_at[0], h * glow_at[1]
    # Drawn small and scaled up: a blur this wide at full size is slow.
    k = 8
    mask = Image.new("L", (w // k, h // k), 0)
    ImageDraw.Draw(mask).ellipse(((cx - r * 0.6) / k, (cy - r * 0.6) / k, (cx + r * 0.6) / k, (cy + r * 0.6) / k), fill=110)
    mask = mask.filter(ImageFilter.GaussianBlur(r / k / 2.5)).resize((w, h), Image.BICUBIC)
    bg.paste(Image.new("RGB", (w, h), GLOW), (0, 0), mask)
    return bg


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def device(capture, height, kind):
    """The capture, scaled to `height` overall, in a dark frame with a highlight edge."""
    bezel_k, radius_k = (0.012, 0.135) if kind == "phone" else (0.018, 0.04)
    sw, sh = capture.size
    bezel = int(height * bezel_k)
    screen_h = height - 2 * bezel
    screen_w = round(screen_h * sw / sh)
    screen = capture.resize((screen_w, screen_h), Image.LANCZOS)
    w, h = screen_w + 2 * bezel, height
    r_screen = int(screen_w * radius_k)
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    draw.rounded_rectangle((0, 0, w - 1, h - 1), r_screen + bezel, fill=(58, 58, 64, 255))
    edge = max(2, bezel // 6)
    draw.rounded_rectangle((edge, edge, w - 1 - edge, h - 1 - edge), r_screen + bezel - edge, fill=(16, 16, 18, 255))
    body.paste(screen, (bezel, bezel), rounded_mask(screen.size, r_screen))
    return body


def place(canvas, dev, x, y, shadow=True):
    """Pastes a device at (x, y) with a soft drop shadow."""
    if shadow:
        pad = int(dev.height * 0.06)
        sh = Image.new("L", (dev.width + 2 * pad, dev.height + 2 * pad), 0)
        sh.paste(dev.getchannel("A").point(lambda v: v * 0.55), (pad, pad))
        sh = sh.filter(ImageFilter.GaussianBlur(pad / 2.5))
        canvas.paste((0, 0, 0), (x - pad, y - pad + pad // 3), sh)
    canvas.paste(dev, (x, y), dev)


def wrap(draw, text, f, width):
    """Greedy lines, then rebalanced so a two-line caption breaks near its middle."""
    lines = greedy(draw, text, f, width)
    if len(lines) == 2:
        words = text.split()
        splits = [(" ".join(words[:i]), " ".join(words[i:])) for i in range(1, len(words))]
        fits = [s for s in splits if max(draw.textlength(p, font=f) for p in s) <= width]
        if fits:
            lines = list(min(fits, key=lambda s: max(draw.textlength(p, font=f) for p in s)))
    return lines


def greedy(draw, text, f, width):
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=f) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def text_block(draw, lines, f, x_center, y, fill, spacing, align="center", x_left=0):
    for line in lines:
        if align == "center":
            draw.text((x_center, y), line, font=f, fill=fill, anchor="ma")
        else:
            draw.text((x_left, y), line, font=f, fill=fill, anchor="la")
        y += int(f.size * spacing)
    return y


def capture(folder, lang, screen):
    return Image.open(SHOTS / folder / lang / "dark" / f"{SCREENS.index(screen) + 1}-{screen}.png").convert("RGB")


def screenshot(size, folder, kind, lang, screen):
    w, h = size
    canvas = background(w, h)
    draw = ImageDraw.Draw(canvas)
    title, sub = CAPTIONS[lang][screen]
    max_w = w * 0.86
    # Sized on the shorter of width and a phone's share of height, so the wide
    # Duo canvases keep the same caption as the tall ones.
    base = min(w, h * 0.46)
    tf, sf = font(base * 0.078, 760), font(base * 0.041, 500)
    t_lines, s_lines = wrap(draw, title, tf, max_w), wrap(draw, sub, sf, max_w)
    y = int(h * 0.055)
    y = text_block(draw, t_lines, tf, w // 2, y, (255, 255, 255), 1.15)
    y = text_block(draw, s_lines, sf, w // 2, y + int(sf.size * 0.35), SUBTLE, 1.25)
    top = y + int(h * 0.035)
    dev_h = h - top - int(h * 0.04)
    shot = capture(folder, lang, screen)
    dev = device(shot, dev_h, kind)
    if dev.width > w * 0.88:
        dev = device(shot, int(dev_h * w * 0.88 / dev.width), kind)
    place(canvas, dev, (w - dev.width) // 2, top)
    return canvas


def header(size, lang):
    """The scoreboard front and centre, the meet list and the schedule behind it."""
    w, h = size
    canvas = background(w, h, glow_at=(0.5, 0.55), glow_size=0.75)
    center_h = int(h * 0.84)
    side_h = int(center_h * 0.86)
    front = device(capture("iphone-6.9", lang, "scoreboard"), center_h, "phone")
    left = device(capture("iphone-6.9", lang, "picker"), side_h, "phone")
    right = device(capture("iphone-6.9", lang, "schedule"), side_h, "phone")
    # The wide header has room to show more of the side screens.
    gap = int(front.width * (0.95 if w / h > 2 else 0.68))
    cy = (h - center_h) // 2
    sy = cy + (center_h - side_h) // 2
    place(canvas, left, w // 2 - gap - left.width // 2, sy)
    place(canvas, right, w // 2 + gap - right.width // 2, sy)
    place(canvas, front, (w - front.width) // 2, cy)
    return canvas


def search(size, lang):
    """The icon and one line on the left, two screens on the right."""
    w, h = size
    canvas = background(w, h, glow_at=(0.72, 0.5), glow_size=0.8)
    draw = ImageDraw.Draw(canvas)
    margin = int(w * 0.07)
    text_w = int(w * 0.36)
    icon_s = int(min(h * 0.2, w * 0.12))
    icon = Image.open(ICON).convert("RGB").resize((icon_s, icon_s), Image.LANCZOS)
    tf = font(min(h * 0.085, w * 0.05), 780)
    nf = font(icon_s * 0.42, 700)
    lines = wrap(draw, CAPTIONS[lang]["search"], tf, text_w)
    block_h = icon_s + int(h * 0.05) + int(tf.size * 1.12) * len(lines)
    y = (h - block_h) // 2
    canvas.paste(icon, (margin, y), rounded_mask(icon.size, int(icon_s * 0.225)))
    draw.text((margin + icon_s + int(icon_s * 0.3), y + icon_s // 2), "Splouch", font=nf, fill=(255, 255, 255), anchor="lm")
    text_block(draw, lines, tf, 0, y + icon_s + int(h * 0.05), (255, 255, 255), 1.12, align="left", x_left=margin)
    front_h = int(h * 0.86)
    back_h = int(front_h * 0.88)
    front = device(capture("iphone-6.9", lang, "scoreboard"), front_h, "phone")
    back = device(capture("iphone-6.9", lang, "results"), back_h, "phone")
    cx = int(w * 0.73)
    place(canvas, back, cx + int(front.width * 0.42) - back.width // 2, (h - back_h) // 2)
    place(canvas, front, cx - int(front.width * 0.42) - front.width // 2, (h - front_h) // 2)
    return canvas


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(path, optimize=True)
    print(path.relative_to(ROOT))


def main():
    for listing, lang in LISTINGS.items():
        base = OUT / listing
        for name, (size, folder, kind) in SIZES.items():
            for i, screen in enumerate(SCREENS, 1):
                save(screenshot(size, folder, kind, lang, screen), base / "screenshots" / name / f"{i}-{screen}.png")
        for w, h in HEADERS:
            save(header((w, h), lang), base / "artwork" / f"header-{w}x{h}.png")
        for w, h in SEARCH:
            save(search((w, h), lang), base / "artwork" / f"search-{w}x{h}.png")


if __name__ == "__main__":
    main()
