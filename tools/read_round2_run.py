#!/usr/bin/env python3
"""One-shot read-only result retrieval; no polling, dispatch or artifact access."""
import base64
import json
from pathlib import Path
import subprocess
import sys
import zlib

REPO='ryoumiyahayato/wwo-economy'


def api(path):
    result=subprocess.run(['gh','api',f'repos/{REPO}/{path}'],capture_output=True,text=True,check=True)
    return json.loads(result.stdout)


def read(run_id):
    run=api(f'actions/runs/{run_id}')
    jobs=api(f'actions/runs/{run_id}/jobs')['jobs']
    checks=[]
    chunks={}
    for job in jobs:
        check_id=job['check_run_url'].rsplit('/',1)[1]
        for annotation in api(f'check-runs/{check_id}/annotations?per_page=100'):
            if annotation.get('title')!='WWO round2':continue
            try:payload=json.loads(annotation['message'])
            except ValueError:
                checks.append({'check':'truncated-annotation','status':'UNVERIFIED','detail':'GitHub truncated the first-run long annotation; see original Actions Summary'})
                continue
            if payload.get('encoding')=='chunk':
                chunks.setdefault(payload['check'],{})[payload['index']]=payload
                continue
            if payload.get('encoding')=='zlib+base64':
                decoder=zlib.decompressobj()
                decoded=decoder.decompress(base64.b64decode(payload['payload']),2*1024*1024)
                if not decoder.eof:raise ValueError('Result annotation exceeds bounded size')
                checks.append(json.loads(decoded))
            elif 'check' in payload:checks.append(payload)
    for name,parts in chunks.items():
        count=next(iter(parts.values()))['count']
        if len(parts)!=count:
            checks.append({'check':name,'status':'UNVERIFIED','detail':'Incomplete annotation chunks'})
            continue
        checks.append(json.loads(zlib.decompress(base64.b64decode(''.join(parts[i]['payload'] for i in range(count))))))
    return {'repository':REPO,'sha':run['head_sha'],'run_url':run['html_url'],
        'status':run['status'],'conclusion':run['conclusion'],
        'created_at':run['created_at'],'updated_at':run['updated_at'],
        'jobs':[{k:j[k] for k in ['id','conclusion','started_at','completed_at','labels']} for j in jobs],
        'checks':checks}


if __name__=='__main__':
    result=read(int(sys.argv[1]))
    Path(sys.argv[2]).write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(result['status'],result['conclusion'],result['sha'])
    for row in result['checks']:
        print(row['status'],row['check'],str(row['detail'])[:1800])
