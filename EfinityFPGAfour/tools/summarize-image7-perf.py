"""Summarize measured simulation cycles; these are not board FPS measurements."""
import json,re,sys
from pathlib import Path
p=Path(sys.argv[1]);text=p.read_text(errors='replace')
m=re.search(r'PROFILE pool=(\d+) glue=(\d+) decode=(\d+) total=(\d+)',text)
assert m,'missing completed numerical regression'
result=dict(zip(['pool','glue','decode','total'],map(int,m.groups())))
names=['idle','weight_req0','weight_wait0','weight_req1','weight_wait1','weight_commit','tile','tile_req','tile_wait','tile_unpack','mac_issue','mac_wait','requant_start','requant_wait','output_req','output_wait','advance','requant_store']
layers={str(i):{} for i in range(10)}
for i,s,c in re.findall(r'PROFILE layer=(\d+) state=(\d+) cycles=(\d+)',text):layers[i][names[int(s)]]=int(c)
result['layers']=layers
result['conv_totals']={name:sum(x.get(name,0) for x in layers.values()) for name in names}
result['clock_hz']=96000000;result['pipeline_ms']=result['total']/96000;result['board_measured']=False
p.with_suffix('.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='layers'},indent=2))
