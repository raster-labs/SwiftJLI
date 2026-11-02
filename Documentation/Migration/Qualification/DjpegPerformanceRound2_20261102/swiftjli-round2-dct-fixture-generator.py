import json,subprocess,pathlib,hashlib,time
root=pathlib.Path('/private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory')
coverage=pathlib.Path('/private/tmp/swiftjli-round2-dct-coverage'); coverage.mkdir(exist_ok=True)
cli='/private/tmp/swiftjli-djpeg642-candidate-build/out/Products/Release/swiftjli-cli'
for bits in (8,12):
 for pattern in ('flat','noise'):
  pgm=coverage/f'{pattern}-{bits}-512.pgm'; jpg=pgm.with_suffix('.jpg')
  if not jpg.exists():
   state=42; maximum=(1<<bits)-1; payload=bytearray()
   for i in range(512*512):
    state=(1664525*state+1013904223)&0xFFFFFFFF
    value=(1<<(bits-1))+1 if pattern=='flat' else (state>>12)&maximum
    payload.extend(value.to_bytes(1 if bits==8 else 2,'big'))
   pgm.write_bytes(f'P5\n512 512\n{maximum}\n'.encode()+payload)
   subprocess.run([cli,'encode','-i',str(pgm),'-o',str(jpg),'--input-format','pgm','--output-format','jpeg','--mode','lossy','--quality','90'],check=True,capture_output=True)
