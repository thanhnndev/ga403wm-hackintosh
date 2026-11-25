# kspin.py <spin> <kext binary> <thread-filter-regex> <root-frame-regex>: self samples by NMXGPU function (symbolicated)
# under frames matching root regex, in threads whose header matches the filter. Inclusive counts per function too.
import re,sys,subprocess,collections
spin,binary,tfilt,root=sys.argv[1:5]
L=open(spin,errors='replace').read().split('\n')
def ind(l): return len(l)-len(l.lstrip(' '))
pat=re.compile(r'^\s*\*?(\d+)\s+\*?(.*)$')
def parse(l):
    m=pat.match(l); 
    if not m: return None
    n=int(m.group(1)); rest=m.group(2)
    k=re.search(r'\((NMXGPU|kernel) \+ (\d+)\)',rest)
    name=('NMX:%s'%k.group(2)) if k and k.group(1)=='NMXGPU' else ('K:%s'%k.group(2) if k else re.sub(r'\s+\+ \d+.*|\s+\(.*','',rest).strip())
    return n,name
selfc=collections.Counter(); incl=collections.Counter(); total=0
i=0; inthread=False
while i<len(L):
    l=L[i]
    if l.startswith('  Thread 0x'): inthread=bool(re.search(tfilt,l)); i+=1; continue
    if inthread and re.search(root,l) and parse(l):
        b=ind(l); n0,_=parse(l); total+=n0
        stack=[]  # (indent,name)
        j=i+1
        while j<len(L) and L[j].strip() and ind(L[j])>b:
            p=parse(L[j])
            if p:
                d=ind(L[j]); n,name=p
                while stack and stack[-1][0]>=d: stack.pop()
                stack.append((d,name))
                ch=0; k=j+1
                while k<len(L) and L[k].strip() and ind(L[k])>d:
                    if ind(L[k])==d+2 or (ind(L[k])>d and ind(L[k])-d<=3 and parse(L[k])):
                        if ind(L[k])-d<=3: ch+=parse(L[k])[0]
                    k+=1
                # nearest NMX frame in stack (deepest) owns the self time if leaf is kernel
                if n-ch>0:
                    owner=next((s for _,s in reversed(stack) if s.startswith('NMX:')),name)
                    selfc[owner]+=n-ch
                if name.startswith('NMX:'): incl[name]+=n
            j+=1
        i=j; continue
    i+=1
offs=sorted({int(k[4:]) for k in list(selfc)+list(incl) if k.startswith('NMX:')})
sym={}
if offs:
    out=subprocess.run(['atos','-o',binary,'-arch','x86_64','-l','0']+[hex(o) for o in offs],capture_output=True,text=True).stdout.split('\n')
    for o,s in zip(offs,out): sym['NMX:%d'%o]=re.sub(r' \(in NMXGPU\)','',s)
def nm(k): return sym.get(k,k)
agg=collections.Counter()
for k,v in selfc.items(): agg[re.sub(r'\s*\+\s*\d+$','',nm(k))]+=v
print('root samples',total)
for k,v in agg.most_common(30): print(f'{v:6d} self  {k[:140]}')
ai=collections.Counter()
for k,v in incl.items(): ai[re.sub(r"\s*\+\s*\d+$","",nm(k))]+=v
print('-- inclusive (max per function)')
for k,v in ai.most_common(40): print(f'{v:6d} incl  {k[:140]}')
