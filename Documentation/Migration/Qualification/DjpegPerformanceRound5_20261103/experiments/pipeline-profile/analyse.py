#!/usr/bin/env python3
"""Disjoint sample counts; frame ancestry attributes callees without summing inclusive counts."""
from pathlib import Path
import re,json,collections
root=Path(__file__).resolve().parent
result={}
def classify(path):
    s='\n'.join(path)
    for category,needle in [('AC entropy','HuffmanDecoder.decodeAC'),('DC entropy','HuffmanDecoder.decodeDC'),('other entropy','HuffmanDecoder.decodeSymbol'),('scatter','scatterWindow'),('compact','compactPixelsInPlace'),('pack dequant','packDequantizedDCTBatch'),('IDCT with caller stack','inverseDCTBatchPacked'),('serial output conversion','writeReconstructedGreyscaleBatch')]:
        if needle in s:return category
    if any(t in s for t in ['semaphore_wait_trap','semaphore_timedwait_trap','__ulock_wait','__psynch_cvwait','mach_msg2_trap','__workq_kernreturn']):return 'waiting'
    if 'libBLAS.dylib' in s:return 'BLAS with incomplete caller stack'
    if 'reconstructWindow' in s:return 'reconstruction other'
    if 'PipelinedGreyscaleDecoder.decode' in s:
        if '_platform_memmove' in s or 'DYLD-STUB$$memcpy' in s:return 'pipeline memcpy / memmove'
        return 'pipeline other / inlined code'
    if 'MarkerReader' in s or 'JPEGCodec.parse' in s:return 'parse / validation'
    return 'other'
for p in sorted(root.glob('*.sample.txt')):
    roots=[];stack=[]
    for line in p.read_text().split('Call graph:',1)[1].split('Total number in stack',1)[0].splitlines():
        m=re.match(r'^([ +!:|]*)(\d+) (.+)$',line)
        if not m:continue
        depth=len(m[1]);node={'count':int(m[2]),'symbol':m[3],'children':[],'depth':depth}
        while stack and stack[-1]['depth']>=depth:stack.pop()
        if stack:stack[-1]['children'].append(node)
        else:roots.append(node)
        stack.append(node)
    records=[]
    for tree in roots:
        counts=collections.Counter();leaf=collections.Counter()
        def visit(node,path):
            path=path+[node['symbol']]
            own=node['count']-sum(child['count'] for child in node['children'])
            assert own>=0,(p,node)
            counts[classify(path)]+=own
            leaf[node['symbol'].split('  (in ')[0]]+=own
            for child in node['children']:visit(child,path)
        visit(tree,[])
        assert sum(counts.values())==tree['count']
        records.append({'thread':tree['symbol'],'samples':tree['count'],
            'categories':dict(counts),'topOwnFrames':leaf.most_common(12)})
    result[p.stem]=records
(root/'sample-summary.json').write_text(json.dumps(result,indent=2)+'\n')
for name,records in result.items():
    print(name)
    for record in records:
        if 'main-thread' in record['thread']:continue
        print(record['thread'],record['samples'],{k:f"{v} ({v/record['samples']*100:.1f}%)" for k,v in record['categories'].items() if v})
