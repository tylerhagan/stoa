# Stoa colour audit. For every theme and colour vision setting, simulates
# each kind of colour blindness (Machado, Oliveira and Fernandes 2009, full
# strength) and checks two things:
#   * text tokens reach 4.5:1 contrast on the theme's panel (WCAG 1.4.3),
#     bar colours 3:1 (WCAG 1.4.11);
#   * states that meet on screen stay apart: CIEDE2000 difference of 15 or
#     more counts as clear, 10 to 15 as close, under 10 as too close.
# Run: python3 Tools/art/cvd_audit.py [--all]
# Needs numpy.
import re, math, sys, json
import numpy as np
import os
ROOT=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..')
src=open(os.path.join(ROOT,'Core','Tokens.lua')).read()
order=[n for n in re.findall(r'"(\w+)"',re.search(r'Stoa.themeOrder = \{(.*?)\}',src,re.S).group(1)) if n!="Class"]
def parse(body): return {k:(h,float(a) if a else 1.0) for k,h,a in re.findall(r'(\w+)\s*=\s*rgb\("(\w{6})"(?:,\s*([\d.]+))?\)',body)}
themes={n:parse(re.search(r'\n\t'+n+r' = \{(.*?)\n\t\},',src,re.S).group(1)) for n in order}
vbody=re.search(r'Stoa.visions = \{(.*?)\n\}\n',src,re.S).group(1)
visions={v:parse(b) for v,b in re.findall(r'\n\t(\w+) = \{(.*?)\n\t\},',vbody,re.S)}
M={'protan':np.array([[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]]),
'deutan':np.array([[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]]),
'tritan':np.array([[1.255528,-0.076749,-0.178779],[-0.078411,0.930809,0.147602],[0.004733,0.691367,0.303900]])}
def lin(c): c=np.asarray(c,float); return np.where(c<=0.04045,c/12.92,((c+0.055)/1.055)**2.4)
def hexrgb(h): return np.array([int(h[i:i+2],16) for i in (0,2,4)])/255
def comp(fg,alpha,bg): return fg*alpha+bg*(1-alpha)  # sRGB-space blend approx
GROUND=np.array([0.04,0.04,0.045])  # dark world behind panels
def sim(rgb,kind):
    l=lin(rgb)
    if kind=='achromat': y=l@[0.2126,0.7152,0.0722]; l=np.array([y,y,y])
    elif kind in M: l=np.clip(M[kind]@l,0,1)
    return l  # linear
def lum(l): return float(l@[0.2126,0.7152,0.0722])
def contrast(a,b):
    la,lb=sorted([lum(a),lum(b)],reverse=True); return (la+0.05)/(lb+0.05)
def lab(l):
    X=l@[0.4124,0.3576,0.1805]/0.95047; Y=l@[0.2126,0.7152,0.0722]; Z=l@[0.0193,0.1192,0.9505]/1.08883
    f=lambda t: t**(1/3) if t>0.008856 else 7.787*t+16/116
    return np.array([116*f(Y)-16,500*(f(X)-f(Y)),200*(f(Y)-f(Z))])
def de2000(l1,l2):
    L1,a1,b1=lab(l1);L2,a2,b2=lab(l2)
    C1=math.hypot(a1,b1);C2=math.hypot(a2,b2);Cb=(C1+C2)/2
    G=0.5*(1-math.sqrt(Cb**7/(Cb**7+25**7)));a1p=(1+G)*a1;a2p=(1+G)*a2
    C1p=math.hypot(a1p,b1);C2p=math.hypot(a2p,b2)
    h1=math.degrees(math.atan2(b1,a1p))%360;h2=math.degrees(math.atan2(b2,a2p))%360
    dL=L2-L1;dC=C2p-C1p
    dh=h2-h1
    if C1p*C2p==0: dh=0
    elif dh>180: dh-=360
    elif dh<-180: dh+=360
    dH=2*math.sqrt(C1p*C2p)*math.sin(math.radians(dh/2))
    Lb=(L1+L2)/2;Cbp=(C1p+C2p)/2
    hb=(h1+h2)/2 if abs(h1-h2)<=180 else (h1+h2+360)/2
    if C1p*C2p==0: hb=h1+h2
    T=1-0.17*math.cos(math.radians(hb-30))+0.24*math.cos(math.radians(2*hb))+0.32*math.cos(math.radians(3*hb+6))-0.2*math.cos(math.radians(4*hb-63))
    SL=1+0.015*(Lb-50)**2/math.sqrt(20+(Lb-50)**2);SC=1+0.045*Cbp;SH=1+0.015*Cbp*T
    RT=-2*math.sqrt(Cbp**7/(Cbp**7+25**7))*math.sin(math.radians(60*math.exp(-((hb-275)/25)**2)))
    return math.sqrt((dL/SL)**2+(dC/SC)**2+(dH/SH)**2+RT*(dC/SC)*(dH/SH))
# pairs that must stay apart (both appear together and mean different things)
PAIRS=[('danger','accent'),('danger','health'),('danger','text'),('mana','health'),('magic','disease'),('danger','mana'),('accent','health'),('danger','disease'),('danger','magic')]
TEXT_TOKENS=['text','muted','accent','danger','magic','disease']
BAR_TOKENS=['health','mana']
VIEW=[('typical',None),('protan','RedGreen'),('deutan','RedGreen'),('tritan','BlueYellow'),('achromat','NoColour')]
def check(t, kind, m):
    pal=dict(t)
    if m: pal.update(visions[m])
    panel=comp(hexrgb(pal['panel'][0]),pal['panel'][1],GROUND)
    P=sim(panel,kind)
    col={k:sim(comp(hexrgb(pal[k][0]),pal[k][1],panel),kind) for k in set(TEXT_TOKENS+BAR_TOKENS)}
    low=[f'{k} {contrast(col[k],P):.1f}:1' for k in TEXT_TOKENS if contrast(col[k],P)<4.5]+[f'{k} {contrast(col[k],P):.1f}:1' for k in BAR_TOKENS if contrast(col[k],P)<3]
    de={f'{a}/{b}':de2000(col[a],col[b]) for a,b in PAIRS}
    return low,de
import sys
show_all='--all' in sys.argv
summary={}
for tn,t in themes.items():
    for kind,mode in VIEW:
        for m in ([None]+([mode] if mode else [])):
            low,de=check(t,kind,m)
            worst=min(de.values())
            close=[f'{p} {v:.0f}' for p,v in de.items() if v<15]
            grade='clear' if worst>=15 and not low else ('close' if worst>=10 and not low else 'fails')
            key=(kind,m or 'Standard'); summary.setdefault(key,[]).append((tn,grade,worst,low,close))
for (kind,m),rows in summary.items():
    counts={g:sum(1 for r in rows if r[1]==g) for g in ('clear','close','fails')}
    print(f'{kind:9} {m:10} clear {counts["clear"]:2}  close {counts["close"]:2}  fails {counts["fails"]:2}   worst pair dE {min(r[2] for r in rows):.0f}')
    if show_all:
        for tn,g,w,low,close in rows:
            if g!='clear': print('    ',tn,g,'; '.join(low+close))
