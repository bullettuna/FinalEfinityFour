"""Independent array reference for image2's documented integer photo pipeline.

Only test-vector generation runs on the PC. The FPGA executes all photo work.
Connected components use an independent Python traversal, not RTL state emulation.
"""
import argparse
from collections import deque
from pathlib import Path
import random


def windows(image):
    h, w = len(image), len(image[0])
    for y in range(h):
        for x in range(w):
            yield y, x, [image[max(0, min(h-1, y+dy))][max(0, min(w-1, x+dx))]
                         for dy in (-1, 0, 1) for dx in (-1, 0, 1)]


def filter_image(image, median):
    out = [[0]*len(image[0]) for _ in image]
    for y, x, p in windows(image):
        out[y][x] = sorted(p)[4] if median else (
            p[0]+p[2]+p[6]+p[8]+2*(p[1]+p[3]+p[5]+p[7])+4*p[4]+8)//16
    return out


def classify(image, median=True, high=60, low=30):
    if median:
        image = filter_image(image, True)
    image = filter_image(image, False)
    h, w = len(image), len(image[0])
    mags = [[0]*w for _ in image]
    dirs = [[0]*w for _ in image]
    for y, x, p in windows(image):
        gx = p[2]+2*p[5]+p[8]-p[0]-2*p[3]-p[6]
        gy = p[0]+2*p[1]+p[2]-p[6]-2*p[7]-p[8]
        a, b = abs(gx), abs(gy)
        mags[y][x] = a+b
        dirs[y][x] = 0 if b*256 <= a*106 else 2 if a*256 <= b*106 else 1 if (gx < 0) == (gy < 0) else 3
    out = [[0]*w for _ in image]
    neighbors = ((3, 5), (2, 6), (1, 7), (0, 8))
    for y, x, p in windows(mags):
        a, b = neighbors[dirs[y][x]]
        if x in (0, w-1) or y in (0, h-1) or not p[4] or p[4] < max(p[a], p[b]):
            continue
        out[y][x] = 2 if p[4] >= high else 1 if p[4] >= min(low, high) else 0
    return out


def components(classes, clean=1, minimum=20):
    h, w = len(classes), len(classes[0])
    seen = set()
    out = [[0]*w for _ in classes]
    for y in range(h):
        for x in range(w):
            if not classes[y][x] or (y, x) in seen:
                continue
            todo = deque([(y, x)])
            seen.add((y, x))
            group = []
            while todo:
                yy, xx = todo.popleft()
                group.append((yy, xx))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = yy+dy, xx+dx
                        if 0 <= ny < h and 0 <= nx < w and classes[ny][nx] and (ny, nx) not in seen:
                            seen.add((ny, nx))
                            todo.append((ny, nx))
            width = max(xx for yy, xx in group)-min(xx for yy, xx in group)+1
            height = max(yy for yy, xx in group)-min(yy for yy, xx in group)+1
            small = len(group) < minimum and (clean == 2 or (width <= 8 and height <= 8))
            keep = any(classes[yy][xx] == 2 for yy, xx in group) and not (clean and small)
            if keep:
                for yy, xx in group:
                    out[yy][xx] = 65535
    return out


def rgb565(v):
    return ((v >> 3) << 11) | ((v >> 2) << 5) | (v >> 3)


def write(path, image):
    path.write_text(''.join(f'{v:04x}\n' for row in image for v in row), encoding='ascii')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--width', type=int, default=32)
    parser.add_argument('--height', type=int, default=24)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    w, h = args.width, args.height
    rng = random.Random(10422)
    flat = [[83]*w for _ in range(h)]
    rectangle = [[210 if w//4 <= x < 3*w//4 and h//4 <= y < 3*h//4 else 30 for x in range(w)] for y in range(h)]
    noise = [[rng.randrange(256) if rng.random() < .12 else rectangle[y][x] for x in range(w)] for y in range(h)]
    diagonal = [[min(255, 12 + (90 if x > y else 0) + (55 if x > 2*w//3 else 0)) for x in range(w)] for y in range(h)]
    for case, image in enumerate((flat, rectangle, noise, diagonal)):
        write(args.output/f'input{case}.hex', image)
        for median in (0, 1):
            classes = classify(image, bool(median))
            write(args.output/f'class{case}_{median}.hex', classes)
            for clean in (0, 1, 2):
                write(args.output/f'edge{case}_{median}_{clean}.hex', components(classes, clean))
            gray = filter_image(image, True) if median else image
            write(args.output/f'gray{case}_{median}.hex', [[rgb565(v) for v in row] for row in gray])
    # Hard hysteresis cases: long weak chain with strong seed at its far end,
    # isolated strong speckle, small closed loop, pure-weak component, borders.
    classes = [[0]*w for _ in range(h)]
    for x in range(1, w-1): classes[2][x] = 1
    classes[2][w-2] = 2
    classes[h-2][1] = 2
    for x in range(4, min(8, w-1)): classes[h-5][x] = classes[h-2][x] = 2
    for y in range(h-5, h-1): classes[y][4] = classes[y][min(7, w-2)] = 2
    for x in range(w//2, w-2): classes[h//2][x] = 1
    write(args.output/'classes.hex', classes)
    for clean in (0, 1, 2): write(args.output/f'components{clean}.hex', components(classes, clean))
    integration = [[200 if 16 <= x < 48 and 2 <= y < 6 else 30 for x in range(64)] for y in range(8)]
    write(args.output/'integration_gray.hex', [[rgb565(v) for v in row] for row in filter_image(integration, True)])
    write(args.output/'integration_edge.hex', components(classify(integration), 1))
    for tint in (40, 80):
        image = []
        for y in range(7, -1, -1):
            row = []
            for x in range(64):
                row.append((sum((54*(2*x+dx)+183*((2*y+dy)*4)+19*tint+128)//256
                                for dy in (0, 1) for dx in (0, 1))+2)//4)
            image.append(row)
        write(args.output/f'video_edge{tint}.hex', components(classify(image, high=20, low=10), 1))
    print(f'PASS generated independent {w}x{h} integer Canny/8-connected reference vectors')


if __name__ == '__main__':
    main()
