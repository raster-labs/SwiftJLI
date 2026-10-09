import json,hashlib,pathlib,sys
from jsonschema.validators import validator_for
from referencing import Registry,Resource
from urllib.parse import urlparse
root=pathlib.Path('work/evidence/final-sbom-direct');schemas=root/'schemas'
def retrieve(uri):
 name=urlparse(uri).path.rsplit('/',1)[-1]
 if name not in {'spdx-json-schema.json','bom-1.7.schema.json','spdx.schema.json','jsf-0.82.schema.json'}:raise ValueError('Unrecorded schema reference: '+uri)
 return Resource.from_contents(json.loads((schemas/name).read_text()))
registry=Registry(retrieve=retrieve)
records=[]
for spec,name in [('spdx','spdx-json-schema.json'),('cyclonedx','bom-1.7.schema.json')]:
 schema=json.loads((schemas/name).read_text());cls=validator_for(schema);cls.check_schema(schema)
 for path in (root/spec).glob('*.json'):
  errors=list(cls(schema,registry=registry,format_checker=cls.FORMAT_CHECKER).iter_errors(json.loads(path.read_text())))
  errors.sort(key=lambda e:str(list(e.path)))
  entry={'file':path.name,'schema':name,'fileSHA256':hashlib.sha256(path.read_bytes()).hexdigest(),'schemaSHA256':hashlib.sha256((schemas/name).read_bytes()).hexdigest(),'validator':'jsonschema 4.25.1','status':'pass' if not errors else 'fail','errors':[{'path':list(e.path),'message':e.message} for e in errors]}
  records.append(entry);print(spec,entry['status'],len(errors))
(root/'schema-results.json').write_text(json.dumps(records,indent=2)+'\n')
sys.exit(0 if all(r['status']=='pass' for r in records) else 1)
