"""Independent array reference and synthetic fixtures for image4 RTL."""
from pathlib import Path
import json, sys

OFFSETS=[(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)]
def around(a,x,y,w,h):
    return [int(0<=x+dx<w and 0<=y+dy<h and a[(y+dy)*w+x+dx]) for dx,dy in OFFSETS]
def properties(a,x,y,w,h):
    n=around(a,x,y,w,h)
    return n,sum(n),sum(not n[k] and n[(k+1)%8] for k in range(8))

def graph_neighbors(a,x,y,w,h):
    n=around(a,x,y,w,h)
    return [p if k%2==0 else int(p and not n[k-1] and not n[(k+1)%8])
            for k,p in enumerate(n)]
def skeleton(a,w,h,limit=32,spur=3):
    a=a.copy();converged=False
    for iteration in range(1,limit+1):
        changed=False
        for phase in range(2):
            removed=[]
            for y in range(h):
                for x in range(w):
                    i=y*w+x
                    if not a[i]:continue
                    n,degree,transitions=properties(a,x,y,w,h)
                    triples=((n[0]*n[2]*n[6],n[0]*n[4]*n[6]) if phase else
                             (n[0]*n[2]*n[4],n[2]*n[4]*n[6]))
                    if 2<=degree<=6 and transitions==1 and not any(triples):removed.append(i)
            for i in removed:a[i]=0
            changed|=bool(removed)
        if not changed:converged=True;break
    pruned=0
    if converged and spur:
        for i in range(w*h):
            x,y=i%w,i//w
            n=graph_neighbors(a,x,y,w,h);degree=sum(n)
            if not a[i] or degree!=1:continue
            path=[i];previous=i
            k=n.index(1);dx,dy=OFFSETS[k];current=(y+dy)*w+x+dx
            while True:
                x,y=current%w,current//w
                n=graph_neighbors(a,x,y,w,h);degree=sum(n)
                if degree>=3:
                    for p in path:a[p]=0
                    pruned+=len(path);break
                if degree!=2 or len(path)>=spur:break
                following=[(y+dy)*w+x+dx for k,(dx,dy) in enumerate(OFFSETS)
                           if n[k] and (y+dy)*w+x+dx!=previous]
                assert len(following)==1
                path.append(current);previous,current=current,following[0]
    ends=branches=0
    for i,p in enumerate(a):
        if p:
            d=sum(graph_neighbors(a,i%w,i//w,w,h))
            ends+=d==1;branches+=d>=3
    return a,dict(iterations=iteration,converged=int(converged),pixels=sum(a),
                  endpoints=ends,branches=branches,pruned=pruned)

def generate(out):
    w=h=32;cases=[]
    def add(name,shape):cases.append((name,[int(shape(x,y)) for y in range(h) for x in range(w)]))
    add('empty',lambda x,y:False)
    add('solid_rectangle',lambda x,y:5<=x<27 and 3<=y<29)
    add('bent_arm',lambda x,y:(5<=x<11 and 5<=y<25) or (8<=x<27 and 20<=y<26))
    add('upper_body',lambda x,y:(12<=x<20 and 5<=y<30) or (3<=x<29 and 7<=y<13))
    add('ring',lambda x,y:4<=x<28 and 4<=y<28 and not(10<=x<22 and 10<=y<22))
    add('truncated_torso',lambda x,y:11<=x<22 or (4<=y<10 and 2<=x<30))
    add('short_spur',lambda x,y:(y==16 and 2<=x<30) or (x==16 and 14<=y<=16))
    add('isolated_lines',lambda x,y:(x==5 and 3<=y<29) or (y==20 and 15<=x<28))
    for limit,name in ((32,'vectors'),(1,'limited')):
        data=[];metadata=[];reports=[]
        for label,a in cases:
            b,r=skeleton(a,w,h,limit)
            if label=='short_spur' and limit==32:
                assert r['pruned']==2 and r['endpoints']==2 and r['branches']==0
            if label=='isolated_lines':assert r['pruned']==0 and r['endpoints']==4
            data.extend(f'{p|(q<<1):x}' for p,q in zip(a,b))
            packed=(r['iterations'] | r['converged']<<8 | r['pixels']<<9 |
                    r['endpoints']<<25 | r['branches']<<41 | r['pruned']<<57)
            metadata.append(f'{packed:020x}');reports.append(dict(case=label,**r))
        (out/f'{name}.mem').write_text('\n'.join(data)+'\n')
        (out/f'{name}_stats.mem').write_text('\n'.join(metadata)+'\n')
        (out/f'{name}.json').write_text(json.dumps(reports,indent=2))
    print('PASS eight independent skeleton reference cases and iteration-limit fixtures')
    fw,fh=120,68
    a=[int(50<=x<70) for y in range(fh) for x in range(fw)]
    b,report=skeleton(a,fw,fh,64)
    (out/'fullhd.mem').write_text('\n'.join(f'{p|(q<<1):x}' for p,q in zip(a,b))+'\n')
    (out/'fullhd.json').write_text(json.dumps(report,indent=2))
if __name__=='__main__':
    out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True);generate(out)
