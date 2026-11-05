import datetime,json,os,pathlib,subprocess
root=pathlib.Path(__file__).parent
repo=pathlib.Path('/private/tmp/swiftjli-djpeg-round5')
commands=[
 ('release-cli',['python3','Scripts/test-cli.py','--binary','/private/tmp/swiftjli-round5-f4a05be-products/swiftjli-cli','--output',str(root/'release-cli')]),
 ('asan-cli',['python3','Scripts/test-cli.py','--binary','/private/tmp/swiftjli-round5-asan/out/Products/Debug/swiftjli-cli','--output',str(root/'asan-cli')]),
 ('lossless-oracle',['python3','Scripts/verify-lossless-interop.py','--output-dir',str(root/'lossless-oracle'),'--scratch-path','/private/tmp/swiftjli-round5-oracle-build','--cjpeg','/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/cjpeg','--djpeg','/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/djpeg']),
 ('dct-oracle',['python3','Scripts/verify-dct-interop.py','--output-dir',str(root/'dct-oracle'),'--scratch-path','/private/tmp/swiftjli-round5-oracle-build','--cjpeg','/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/cjpeg','--djpeg','/opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/djpeg'])]
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
r={'sourceRevision':'f4a05be9f3003a48adaa840abd48fcf6071f009d','status':'running','commands':[]}
for name,command in commands:
 record={'name':name,'command':command,'startedUTC':now()};r['commands'].append(record)
 (root/'cli-oracle-commands.json').write_text(json.dumps(r,indent=2)+'\n')
 with (root/(name+'.log')).open('w') as log:
  result=subprocess.run(command,cwd=repo,env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'),stdout=log,stderr=subprocess.STDOUT)
 record.update(exitCode=result.returncode,finishedUTC=now());r['status']='running' if result.returncode==0 else 'failed'
 (root/'cli-oracle-commands.json').write_text(json.dumps(r,indent=2)+'\n')
 print(name,'exit',result.returncode,flush=True)
 if result.returncode:raise SystemExit(result.returncode)
r['status']='passed';(root/'cli-oracle-commands.json').write_text(json.dumps(r,indent=2)+'\n')
