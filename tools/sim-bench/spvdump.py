# SPDX-License-Identifier: BSD-3-Clause-Clear
# spvdump.py module.spv - minimal SPIR-V lister (no spirv-dis on this Mac): opcode name + operand ids
import struct,sys
OPS={5:'Name',15:'EntryPoint',19:'TypeVoid',20:'TypeBool',21:'TypeInt',22:'TypeFloat',23:'TypeVector',28:'TypeArray',29:'TypeRuntimeArray',30:'TypeStruct',32:'TypePointer',33:'TypeFunction',43:'Constant',54:'Function',55:'FunctionParameter',56:'FunctionEnd',57:'FunctionCall',59:'Variable',61:'Load',62:'Store',65:'AccessChain',66:'InBoundsAccessChain',67:'PtrAccessChain',70:'InBoundsPtrAccessChain',71:'Decorate',72:'MemberDecorate',79:'VectorShuffle',80:'CompositeConstruct',81:'CompositeExtract',83:'CopyObject',113:'UConvert',114:'SConvert',124:'Bitcast',128:'IAdd',130:'ISub',132:'IMul',134:'UDiv',137:'UMod',194:'ShiftRightLogical',196:'ShiftLeftLogical',199:'BitwiseAnd',248:'Label',249:'Branch',253:'Return',254:'ReturnValue',245:'Phi',77:'VectorExtractDynamic'}
d=open(sys.argv[1],'rb').read(); w=struct.unpack('<%dI'%(len(d)//4),d)
i=5; out=[]
while i<len(w):
  n=w[i]>>16; op=w[i]&0xffff; out.append((op,w[i+1:i+n])); i+=n
for op,a in out:
  nm=OPS.get(op,str(op))
  if op==5: print('Name %%%d %s'%(a[0],bytes(struct.pack('<%dI'%(len(a)-1),*a[1:])).split(b'\0')[0].decode())); continue
  if op in (71,72): continue
  print(nm,' '.join('%'+str(x) for x in a))
