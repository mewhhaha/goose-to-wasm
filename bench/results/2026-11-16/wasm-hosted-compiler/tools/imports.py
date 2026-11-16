import sys
b=open(sys.argv[1],'rb').read()
def leb(i):
    r=0;s=0
    while True:
        c=b[i]; i+=1; r|=(c&0x7f)<<s; s+=7
        if c<0x80: return r,i
i=8; types=[]; T={0x7f:'i32',0x7e:'i64',0x7d:'f32',0x7c:'f64'}
while i<len(b):
    sid=b[i]; i+=1; size,i=leb(i); end=i+size
    if sid==1:
        n,j=leb(i)
        for _ in range(n):
            assert b[j]==0x60; j+=1
            pc,j=leb(j); ps=[T[b[j+k]] for k in range(pc)]; j+=pc
            rc,j=leb(j); rs=[T[b[j+k]] for k in range(rc)]; j+=rc
            types.append((ps,rs))
    if sid==2:
        n,j=leb(i)
        for _ in range(n):
            l,j=leb(j); mod=b[j:j+l].decode(); j+=l
            l,j=leb(j); name=b[j:j+l].decode(); j+=l
            kind=b[j]; j+=1
            if kind==0:
                t,j=leb(j); print('%s.%s (%s) -> (%s)'%(mod,name,', '.join(types[t][0]),', '.join(types[t][1])))
            else: print(mod,name,'kind',kind); break
    if sid==5:
        n,j=leb(i); flags=b[j]; j+=1; mn,j=leb(j); mx=None
        if flags&1: mx,j=leb(j)
        print('memory pages initial',mn,'max',mx)
    if sid==10: print('code section bytes',size)
    if sid==11: print('data section bytes',size)
    i=end
