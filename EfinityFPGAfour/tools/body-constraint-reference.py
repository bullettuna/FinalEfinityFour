"""Array/graph oracle for the evidence-only upper-body RTL (no cycle model).

Synthetic masks exercise connectivity and geometric rejection. These checks do
not measure human-recognition accuracy; real camera testing remains necessary.
"""
from collections import deque
from importlib.util import spec_from_file_location, module_from_spec
from pathlib import Path
import json, sys

spec=spec_from_file_location('thin',Path(__file__).with_name('skeleton-reference.py'))
thin=module_from_spec(spec);spec.loader.exec_module(thin)
OFF=thin.OFFSETS

def constrain(mask, raw, w, h, previous=None, max_endpoints=32):
    result=[0]*(w*h)
    def finish(valid=False, flags=0, overflow=False, prior=None):
        return result,dict(valid=int(valid),arms=flags,overflow=int(overflow)),prior
    occupied=[(i%w,i//w) for i,p in enumerate(mask) if p]
    if not occupied:return finish()
    xmin=min(x for x,y in occupied);xmax=max(x for x,y in occupied)
    ymin=min(y for x,y in occupied);ymax=max(y for x,y in occupied)
    height=ymax-ymin+1
    if height<8:return finish()
    lower=ymin+2*height//3
    support=(3*(ymax-lower+1)+3)//4
    runs=[];run=[]
    for x in range(w+1):
        if x<w and sum(mask[y*w+x] for y in range(lower,h))>=support:run.append(x)
        else:
            if run:runs.append(run)
            run=[]
    target=previous['cx'] if previous else (xmin+xmax)//2
    runs.sort(key=lambda r:(-len(r),abs(r[(len(r)-1)//2]-target),r[0]))
    if not runs or len(runs[0])<3:return finish()
    torso=runs[0];cx=torso[(len(torso)-1)//2];margin=max(1,len(torso)//4)
    nodes={i for i in range(w*h) if mask[i] and raw[i]}
    roots=[i for i in sorted(nodes) if i%w in torso and i//w>=ymin+height//2]
    if not roots:return finish()
    root=min(roots,key=lambda i:4*abs(i%w-cx)+ymax-i//w)
    def neighbors(i):
        x,y=i%w,i//w
        return [(y+dy)*w+x+dx for dx,dy in OFF
                if 0<=x+dx<w and 0<=y+dy<h and (y+dy)*w+x+dx in nodes]
    parents={root:None};todo=deque([root]);ends=[];top=root
    while todo:
        node=todo.popleft();x,y=node%w,node//w
        if abs(x-cx)<=margin and (y,abs(x-cx))<(top//w,abs(top%w-cx)):top=node
        adjacent=neighbors(node)
        for other in adjacent:
            if other not in parents:parents[other]=node;todo.append(other)
        if len(adjacent)==1 and node!=root and abs(x-cx)>margin:ends.append(node)
    if len(ends)>max_endpoints:return finish(overflow=True)
    th=root//w-top//w
    if th<3 or th<height//4:return finish()
    cursor=top
    while cursor is not None:result[cursor]=1;cursor=parents[cursor]
    candidates={}
    for endpoint in ends:
        right=endpoint%w>cx;path=[];cursor=endpoint
        while result[cursor]!=1:
            path.append(cursor);cursor=parents[cursor]
        wrong=sum((p%w+margin<cx if right else p%w>cx+margin) for p in path)
        if not(max(3,th//4)<=len(path)<=th*4+len(torso) and
               cursor//w<=top//w+th//2+1 and wrong*3<=len(path)):continue
        distance=0
        if previous and right in previous['ends']:
            px,py=previous['ends'][right]
            distance=abs(endpoint%w-(px+cx-previous['cx']))+abs(endpoint//w-(py+root//w-previous['root_y']))
        score=max(1,len(path)*4+abs(endpoint%w-cx)*2-distance//2)
        if right not in candidates or score>candidates[right][0]:
            candidates[right]=(score,path,endpoint)
    if len(candidates)==2 and candidates[False][1][-1]==candidates[True][1][-1]:
        del candidates[candidates[False][0]>=candidates[True][0]]
    flags=0;prior=dict(cx=cx,root_y=root//w,ends={})
    for right,(_,path,endpoint) in candidates.items():
        flags|=1<<int(right);prior['ends'][right]=(endpoint%w,endpoint//w)
        for p in path:
            if not result[p]:result[p]=3 if right else 2
    assert all(not c or (mask[i] and raw[i]) for i,c in enumerate(result))
    return finish(True,flags,False,prior)

def fixtures(w=32,h=32):
    cases=[]
    def add(name,predicate):
        a=[int(predicate(x,y)) for y in range(h) for x in range(w)]
        b,_=thin.skeleton(a,w,h)
        cases.append((name,a,b))
    add('T',lambda x,y:12<=x<20 and 5<=y<31 or 2<=x<30 and 7<=y<12)
    add('wide',lambda x,y:10<=x<22 and 5<=y<31 or 1<=x<31 and 6<=y<11)
    add('slim',lambda x,y:14<=x<18 and 5<=y<31 or 3<=x<29 and 6<=y<10)
    add('one_arm',lambda x,y:12<=x<20 and 5<=y<31 or 2<=x<17 and 7<=y<12)
    add('raised',lambda x,y:12<=x<20 and 8<=y<31 or 7<=x<25 and 8<=y<13 or 5<=x<10 and 1<=y<13 or 22<=x<27 and 1<=y<13)
    add('bent',lambda x,y:12<=x<20 and 5<=y<31 or 4<=x<28 and 7<=y<12 or 2<=x<7 and 7<=y<20 or 25<=x<30 and 7<=y<20)
    add('lower_spurs',lambda x,y:12<=x<20 and 5<=y<31 or 2<=x<30 and 7<=y<12 or 7<=x<25 and 24<=y<28)
    add('translated',lambda x,y:15<=x<23 and 6<=y<32 or 5<=x<32 and 8<=y<13)
    add('rectangle',lambda x,y:10<=x<22 and 3<=y<31)
    add('empty',lambda x,y:False)
    add('too_small',lambda x,y:12<=x<20 and 15<=y<20)
    add('ring',lambda x,y:3<=x<29 and 3<=y<29 and not (7<=x<25 and 7<=y<25))
    # Disconnected skeleton outside the mask must never appear in the output.
    a=cases[0][1].copy();b=cases[0][2].copy()
    for y in range(4,29):b[y*w]=1
    cases.append(('outside_mask',a,b))
    # Connected lower branches cannot replace the upper arm attachment.
    a=[int(11<=x<=21 and 3<=y<=31 or y in (7,25) and 1<=x<=30) for y in range(h) for x in range(w)]
    b=[int(x==16 and 4<=y<=30 or y in (7,25) and 1<=x<=30) for y in range(h) for x in range(w)]
    cases.append(('low_attachment_graph',a,b))
    # More than the bounded endpoint capacity invalidates the whole model.
    a=[int(11<=x<=21 or y==5 and 1<=x<=30) for y in range(h) for x in range(w)]
    b=[int(x==16 or y%3==2 and 1<=x<=30) for y in range(h) for x in range(w)]
    cases.append(('bounded_overflow',a,b))
    return cases

def generate(out):
    previous=None;data=[];reports=[]
    for name,mask,raw in fixtures():
        result,report,previous=constrain(mask,raw,32,32,previous,max_endpoints=8)
        if name in ('T','wide','slim','raised','bent','translated','outside_mask','low_attachment_graph'):
            assert report['valid'] and report['arms']==3,(name,report)
        if name=='one_arm':assert report['arms']==1
        if name=='low_attachment_graph':assert all(c<2 for i,c in enumerate(result) if i//32>=24)
        if name in ('empty','too_small'):assert not report['valid']
        if name=='bounded_overflow':assert report['overflow'] and not report['valid']
        data.extend(f'{m|(s<<1)|(c<<2):x}' for m,s,c in zip(mask,raw,result))
        reports.append(dict(case=name,**report,pixels=sum(bool(c) for c in result)))
    (out/'body.mem').write_text('\n'.join(data)+'\n')
    (out/'body_stats.mem').write_text('\n'.join(f"{r['valid']|(r['arms']<<1)|(r['overflow']<<3):x}" for r in reports)+'\n')
    (out/'body.json').write_text(json.dumps(reports,indent=2))
    # Independent end-to-end fixtures start from the same production thinning oracle.
    original=[];stats=[];previous=None
    for case in range(8):
        mask=[int(v,16)&1 for v in (out/'vectors.mem').read_text().splitlines()[case*1024:(case+1)*1024]]
        raw,_=thin.skeleton(mask,32,32)
        result,report,previous=constrain(mask,raw,32,32,previous)
        original.extend(f'{c:x}' for c in result);stats.append(report['valid']|(report['arms']<<1))
    (out/'body_video.mem').write_text('\n'.join(original)+'\n')
    (out/'body_video_stats.mem').write_text('\n'.join(f'{s:x}' for s in stats)+'\n')
    previous=None;large=[];large_stats=[]
    for shift,one_arm in ((0,False),(8,False),(0,True)):
        w,h=120,68
        mask=[int(48+shift<=x<72+shift and 8<=y<68 or
                  12+shift<=x<(60+shift if one_arm else 108+shift) and 12<=y<24)
              for y in range(h) for x in range(w)]
        raw,_=thin.skeleton(mask,w,h,64)
        result,report,previous=constrain(mask,raw,w,h,previous)
        assert report['valid'] and report['arms']==(1 if one_arm else 3),report
        large.extend(f'{m|(s<<1)|(c<<2):x}' for m,s,c in zip(mask,raw,result))
        large_stats.append(report['valid']|(report['arms']<<1))
    (out/'body_full.mem').write_text('\n'.join(large)+'\n')
    (out/'body_full_stats.mem').write_text('\n'.join(f'{s:x}' for s in large_stats)+'\n')
    print(f'PASS independent upper-body graph oracle: {len(reports)} fixtures, width/pose/translation, missing arm, rejection and overflow')

if __name__=='__main__':generate(Path(sys.argv[1]))
