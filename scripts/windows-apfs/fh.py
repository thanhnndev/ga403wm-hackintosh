# tracev3 -> "t_sec  pid  strings" per firehose entry (timestamps = continuous time since boot)
import sys,re,struct,lz4.block
fn,out=sys.argv[1],sys.argv[2]
d=open(fn,'rb').read(); o=open(out,'w',encoding='utf-8')
def chunks(buf):
    i=0
    while i+16<=len(buf):
        tag,sub,sz=struct.unpack_from('<IIQ',buf,i)
        yield tag,buf[i+16:i+16+sz]
        i+=16+sz; i=(i+7)&~7
def firehose(c):
    fp,sp=struct.unpack_from('<QI',c,0)
    pub=struct.unpack_from('<H',c,16)[0]
    base=struct.unpack_from('<Q',c,24)[0]
    j=32; end=16+pub
    while j+24<=end:
        at,lt,fl,fmt,tid,dlo,dhi,dsz=struct.unpack_from('<BBHIQIHH',c,j)
        if at==0: break
        t=base+dlo+(dhi<<32)
        body=c[j+24:j+24+dsz]
        ss=[s.decode() for s in re.findall(rb'[\x20-\x7e]{4,}',body)]
        if ss: o.write('%.6f\t%d\t%s\n'%(t/1e9,fp,' | '.join(ss)))
        j+=24+dsz; j=(j+7)&~7
n=0
for tag,c in chunks(d):
    if tag!=0x600d: continue
    if c[:4]!=b'bv41': continue
    usz,csz=struct.unpack_from('<II',c,4)
    try: u=lz4.block.decompress(c[12:12+csz],uncompressed_size=usz)
    except Exception: continue
    for t2,cc in chunks(u):
        if t2==0x6001:
            try: firehose(cc); n+=1
            except Exception: pass
print('firehose chunks',n)
