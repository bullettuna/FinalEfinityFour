"""Generate independent arithmetic corner vectors for the image6 RTL."""
import argparse
from fractions import Fraction
from pathlib import Path
import random


def q(v,m,s,z):
    return max(0,min(65535,round(Fraction(v*m,1<<s))+z))


def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True);r=random.Random(2706)
    rows=[]
    for i in range(500):
        v=r.randrange(-(1<<46),1<<46) if i<150 else r.randrange(-(1<<36),1<<36)
        if i<67:v=i-33
        m,s=(1<<30,31) if i<67 else (r.randrange(1<<30,1<<31),r.randrange(26,57))
        z=r.randrange(65536);relu=r.randrange(2);pm=r.randrange(1<<30,1<<31);ps=r.randrange(27,34);oz=r.randrange(65536)
        first=q(v,m,s,z)-z
        if relu:first=max(0,first)
        expected=q(first,pm,ps,oz)
        values=[v&((1<<48)-1),m,s,z,relu,pm,ps,oz,expected]
        rows.append(' '.join(f'{x:x}' for x in values))
    (a.output/'requant.vec').write_text('\n'.join(rows)+'\n')
    rows=[]
    for n in [1,2,9,16,144,432]:
        bias=[r.randrange(-(1<<31),1<<31) for _ in range(16)]
        total=bias[:];terms=[]
        for k in range(n):
            x=r.randrange(-65535,65536);w=[r.randrange(-32768,32768) for _ in range(16)]
            total=[b+x*v for b,v in zip(total,w)]
            terms.append(f'{x&0x1ffff:x} '+''.join(f'{v&65535:04x}' for v in w[::-1]))
        pack=lambda v:''.join(f'{x&((1<<48)-1):012x}' for x in v[::-1])
        rows.append(f'{n:d} {pack(bias)} {pack(total)}');rows.extend(terms)
    (a.output/'mac.vec').write_text('\n'.join(rows)+'\n')
    print('Generated 500 wide-product/RNE cases and six sixteen-lane MAC sequences')


if __name__=='__main__':main()
