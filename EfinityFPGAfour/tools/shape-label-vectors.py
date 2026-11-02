"""Independent full-frame oracle for Chinese text, box colours and clipping."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("--width", type=int, default=640)
parser.add_argument("--height", type=int, default=240)
parser.add_argument("--preview", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
if args.preview:
    Image.open(args.output / "shape_labels_actual.ppm").save(args.output / "shape_labels_actual.png")
    raise SystemExit(0)
w, h = args.width, args.height
font = ImageFont.truetype("C:/Windows/Fonts/Noto Sans SC (TrueType).otf", 16)
# x_min, x_max, y_min, y_max, classification, valid
frames = [
    [(50,250,80,150,1,True), (360,550,160,220,2,True)],
    [(50,250,80,150,2,True), (360,550,160,220,1,True)],
    [(w-10,w-2,2,70,1,True), (3,170,h-10,h-2,2,True)],
    [(50,250,80,150,0,True), (360,550,160,220,2,False)],
    [(50,250,80,150,2,True), (50,250,80,150,1,True)],
]
colours = {0:(255,255,0), 1:(0,255,0), 2:(0,191,255)}
with (args.output / "shape_labels_expected.mem").open("w", encoding="ascii") as golden:
    for frame_index, boxes in enumerate(frames):
        image = Image.new("RGB", (w,h))
        pixels = image.load()
        for y in range(h):
            for x in range(w):
                pixels[x,y] = (180+x%40,180+y%40,180+(x+y)%40)
                if x == w//2:
                    pixels[x,y] = (255,0,0)
        draw = ImageDraw.Draw(image)
        draw.rectangle((8,8,w-9,h-9), outline=(255,0,255), width=2)
        # Box 1 has precedence over box 2, as in the existing renderer.
        for xmin,xmax,ymin,ymax,kind,valid in reversed(boxes):
            if valid:
                draw.rectangle((xmin,ymin,xmax,ymax), outline=colours[kind], width=3)
        for xmin,_,ymin,_,kind,valid in reversed(boxes):
            if not valid or kind not in (1,2) or w < 168 or h < 40:
                continue
            label_x = min(xmin,w-168)
            label_y = min(ymin-44 if ymin >= 44 else ymin+4,h-40)
            phrase = "检测到圆形" if kind == 2 else "检测到矩形"
            mask = Image.new("L",(80,16))
            pen = ImageDraw.Draw(mask)
            for i,char in enumerate(phrase):
                pen.text((i*16,0),char,font=font,fill=255,anchor="lt")
            mask = mask.point(lambda p: 255 if p >= 96 else 0)
            mask = mask.resize((160,32),Image.Resampling.NEAREST)
            draw.rectangle((label_x,label_y,label_x+167,label_y+39),fill=(32,32,32))
            image.paste(colours[kind],(label_x+4,label_y+4,label_x+164,label_y+36),mask)
        for r,g,b in image.get_flattened_data():
            golden.write(f"{r:02x}{g:02x}{b:02x}\n")
print(f"Generated {len(frames)} oracle frames, {w}x{h}")
