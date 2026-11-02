"""Verify actual image1 port connections, including RGB gradient inputs.

This complements the RTL regression: a standalone median test cannot detect
the top-level accidentally continuing to feed raw RGB into Canny.
"""
from pathlib import Path
import re

root=Path(__file__).resolve().parents[1]
top=(root/'example_top.v').read_text(encoding='utf-8-sig')
wrapper=(root/'images/image1_vision/image1_top.v').read_text(encoding='utf-8-sig')
assert re.search(r'\.CANNY_MEDIAN_BUILD\(1\x27b1\)',wrapper), 'image1 median gate disabled'
assert re.search(r'parameter\s+CANNY_MEDIAN_BUILD\s*=\s*1\x27b0',top), 'other profiles should retain their default'

def ports(name):
    match=re.search(r'\b'+re.escape(name)+r'\s*\((.*?)\);',top,re.S)
    assert match, f'missing instance {name}'
    return {m[0]:re.sub(r'\s+','',m[1]) for m in re.findall(r'\.(\w+)\s*\(([^()]*)\)',match[1])}

canny=ports('u_canny_edge')
for port,value in {'per_frame_vsync':'w_canny_in_vsync','per_frame_href':'w_canny_in_href',
                   'per_frame_hsync':'w_canny_in_hsync','per_img_gray':'w_canny_in_gray',
                   'per_img_red':'PERSON_BUILD?w_canny_in_gray:w_canny_in_r',
                   'per_img_green':'PERSON_BUILD?w_canny_in_gray:w_canny_in_g',
                   'per_img_blue':'PERSON_BUILD?w_canny_in_gray:w_canny_in_b'}.items():
    assert canny.get(port)==value, f'Canny bypasses median: {port}'
median=ports('u_median_frontend')
for port,value in {'median_enable_req':'r_median_enable_active','post_img_gray':'w_median_pixel',
                   'post_img_red':'w_canny_in_r','post_img_green':'w_canny_in_g','post_img_blue':'w_canny_in_b',
                   'post_original_gray':'w_canny_original_gray','post_frame_vsync':'w_median_vsync',
                   'post_frame_href':'w_median_href','post_frame_hsync':'w_median_hsync'}.items():
    assert median.get(port)==value, f'frontend output disconnected: {port}'
aligned=ports('u_original_gray_alignment')
assert aligned['in_gray']=='w_canny_original_gray', 'split original gray misses median center delay'
for port,value in {'in_vsync':'w_canny_in_vsync','in_href':'w_canny_in_href','in_hsync':'w_canny_in_hsync'}.items():
    assert aligned[port]==value, 'split timing bypasses median'
for suffix in ['vsync','href','hsync']:
    assert re.search(r'assign\s+w_canny_in_'+suffix+r'\s*=\s*w_median_'+suffix+r'\s*;',top)
assert re.search(r'assign\s+w_canny_in_gray\s*=\s*w_median_pixel\s*;',top)
print('PASS image1 M -> aligned gray/RGB median -> actual Canny; unfiltered split receives matched center delay')

frontend=(root/'src/vision/image1_median_frontend.v').read_text()
assert 'median_active ? filtered_vs' not in frontend, 'M must not mux video timing'
assert 'u_shared_window' in frontend, 'shared median window missing'
assert '.DATA_WIDTH(32)' in frontend, 'luma/RGB must share coordinates'
assert 'image1_video_mux' in top and 'g_image1_video_output' in top
mux=ports('u_video_mux')
assert mux['out_href']=='w_selected_video_href'
assert mux['out_rgb']=='w_selected_video_rgb'
print('PASS fixed-latency median timing and registered image1 output mux')

mux_rtl=(root/'src/vision/image1_video_mux.v').read_text()
assert 'out_vsync<=aligned_vs[5]' in mux_rtl
assert 'out_hsync<=aligned_hs[5]' in mux_rtl
assert 'out_href<=aligned_de[5]' in mux_rtl
assert 'in_vsync[source_active]' not in mux_rtl, 'display mode must not change sync phase'
print('PASS all image1 display modes use one fixed HDMI sync phase')
