"""Outer identity/receipt controls; no codec or timed-region changes."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,re,subprocess,traceback

ROOT=Path(__file__).resolve().parent
sha=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()

def arguments(action):
    parser=argparse.ArgumentParser()
    parser.add_argument('--run-name',required=True)
    parser.add_argument('--cpu-grant',action='store_true')
    args=parser.parse_args()
    assert args.cpu_grant,'Current parent CPU grant required'
    assert re.fullmatch(r'[a-z0-9][a-z0-9_-]*',args.run_name),'Invalid run name'
    folder=ROOT/'runs'/args.run_name
    folder.mkdir(parents=True,exist_ok=True)
    assert not (folder/(action+'.json')).exists(),'Refusing to overwrite an earlier receipt'
    return folder

def write(path,value):
    temporary=path.with_name(path.name+'.tmp')
    temporary.write_text(json.dumps(value,indent=2)+'\n')
    temporary.replace(path)

def load_plan():
    plan=json.loads((ROOT/'prepared.json').read_text())
    assert plan.get('artifactsReady') is True,'Release artifacts are not pinned; source-only preparation'
    expected={**plan['sourceSHA256'],**plan['productionSourceSHA256'],**plan['importedSHA256'],
              **plan['referenceSHA256'],**plan['toolSHA256'],**plan['fixtureSHA256']}
    assert all(sha(path)==digest for path,digest in expected.items()),'Pinned input identity drift'
    revision=subprocess.check_output(['git','-C',plan['worktree'],'rev-parse','HEAD'],text=True).strip()
    assert revision==plan['sourceRevision'],'Candidate source revision drift'
    baseline_revision=subprocess.check_output(['git','-C',plan['baseline']['worktree'],'rev-parse','HEAD'],text=True).strip()
    assert baseline_revision==plan['baseline']['sourceRevision'],'Baseline source revision drift'
    return plan,expected

def check_after(record,plan,expected,binary=None):
    record['inputsUnchanged']=all(sha(path)==digest for path,digest in expected.items())
    record['planUnchanged']=sha(ROOT/'prepared.json')==record['preparedSHA256']
    record['sourceRevisionUnchanged']=subprocess.check_output(
        ['git','-C',plan['worktree'],'rev-parse','HEAD'],text=True).strip()==plan['sourceRevision']
    record['baselineRevisionUnchanged']=subprocess.check_output(
        ['git','-C',plan['baseline']['worktree'],'rev-parse','HEAD'],text=True).strip()==plan['baseline']['sourceRevision']
    if binary is not None:
        record['binaryUnchanged']=sha(binary)==record['binarySHA256']
    assert all(record[key] for key in ['inputsUnchanged','planUnchanged','sourceRevisionUnchanged','baselineRevisionUnchanged']),'Post-run identity drift'
    if binary is not None: assert record['binaryUnchanged'],'Post-run binary drift'

def host_load():
    rows=[]
    for line in subprocess.check_output(['ps','-axo','pid,pcpu,comm'],text=True,timeout=10).splitlines()[1:]:
        values=line.split(None,2)
        if len(values)==3 and float(values[1])>=10:
            rows.append({'pid':int(values[0]),'cpuPercent':float(values[1]),'process':values[2]})
    return rows

class Commands:
    def __init__(self,folder,record,path):
        self.folder,self.record,self.path=folder,record,path
    def run(self,command,timeout=90):
        index=len(self.record['commands'])
        entry={'command':command,'startedUTC':now()}
        stem=self.path.stem+'-command-%03d'%index
        entry['stdout']=stem+'.stdout.log';entry['stderr']=stem+'.stderr.log'
        self.record['commands'].append(entry);write(self.path,self.record)
        try:
            process=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
            (self.folder/entry['stdout']).write_bytes(process.stdout)
            (self.folder/entry['stderr']).write_bytes(process.stderr)
            entry.update(exitCode=process.returncode,finishedUTC=now())
            write(self.path,self.record)
            process.check_returncode()
            return process
        except subprocess.TimeoutExpired as error:
            for name in ['stdout','stderr']:
                data=getattr(error,name,None)
                if data is not None:
                    (self.folder/entry[name]).write_bytes(data if isinstance(data,bytes) else data.encode())
            entry.update(status='timeout',finishedUTC=now());write(self.path,self.record)
            raise

def record_failure(record,error,folder):
    record.update(status='failed',failureType=type(error).__name__,failure=str(error))
    stamp=now().replace(':','-')
    (folder/('runner-error-'+stamp+'.txt')).write_text(traceback.format_exc())
