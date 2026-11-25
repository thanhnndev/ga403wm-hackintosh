# Minimal Mach-O 64 reader: header, load commands, sections, symtab.
import struct
def parse(d):
    magic,cpu,sub,ft,ncmds,sz,flags,_=struct.unpack_from('<IiiIIIII',d,0)
    assert magic==0xfeedfacf, hex(magic)
    off=32; cmds=[]; secs=[]; sym=None; dysym=None; other=[]
    for _ in range(ncmds):
        cmd,cs=struct.unpack_from('<II',d,off)
        if cmd==0x19:
            seg=d[off+8:off+24].rstrip(b'\0').decode()
            vm,vs,fo,fs,mp,ip,ns,fl=struct.unpack_from('<QQQQiiII',d,off+24)
            cmds.append(('SEG',seg,vm,vs,fo,fs,ns))
            so=off+72
            for i in range(ns):
                sn=d[so:so+16].rstrip(b'\0').decode(); sg=d[so+16:so+32].rstrip(b'\0').decode()
                a,s,o,al,ro,nr,f=struct.unpack_from('<QQIIIII',d,so+32)
                secs.append(dict(seg=sg,sect=sn,addr=a,size=s,off=o,reloff=ro,nreloc=nr,flags=f)); so+=80
        elif cmd==0x2:
            sym=struct.unpack_from('<IIII',d,off+8)
        elif cmd==0xb:
            dysym=struct.unpack_from('<18I',d,off+8)
        else: other.append((hex(cmd),cs))
        off+=cs
    return dict(ft=ft,ncmds=ncmds,flags=flags,cmds=cmds,secs=secs,sym=sym,dysym=dysym,other=other)
def symbols(d,info):
    so,ns,stro,strs=info['sym']; out=[]
    for i in range(ns):
        sx,ty,sc,de,v=struct.unpack_from('<IBBHQ',d,so+16*i)
        e=d.index(b'\0',stro+sx); out.append((i,d[stro+sx:e].decode('latin1'),ty,sc,de,v))
    return out
