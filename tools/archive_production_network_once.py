#!/usr/bin/env python3
"""One-use archive of already verified immutable runs; never runs Godot."""
import gzip,hashlib,json,os,subprocess,tempfile,zipfile
from pathlib import Path
REPO='ryoumiyahayato/wwo-economy'
TARGET='4ee7b330c9bf0c350eee8c0692d131941099b06f'
BASE='f56bc96f5b9d50b20a1573f9ed9ed5c304c829cf'
TAG='production-network-v1-20261025'
ROOT=Path(__file__).resolve().parents[1]
assert os.environ['GITHUB_REPOSITORY']==REPO and os.environ['GITHUB_REF']=='refs/heads/sandbox/main'
def gh(*args):return subprocess.check_output(['gh',*args],text=True,timeout=90)
def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def read_run(run,job,sha,count):
 meta=json.loads(gh('api',f'repos/{REPO}/actions/runs/{run}'))
 assert meta['head_sha']==sha and meta['conclusion']=='success'
 logs=gh('api','--allow-escape-sequences',f'repos/{REPO}/actions/jobs/{job}/logs')
 rows=[json.loads(line.split('NETWORK_CASE ',1)[1]) for line in logs.splitlines() if 'NETWORK_CASE ' in line]
 prov=[json.loads(line.split('NETWORK_PROVENANCE ',1)[1]) for line in logs.splitlines() if 'NETWORK_PROVENANCE ' in line]
 assert len(rows)==count and len(prov)==1 and prov[0]['sha']==sha and 'NETWORK_SUITE_PASS' in logs
 return {'sha':sha,'run_url':meta['html_url'],'cases':rows},prov[0]
with tempfile.TemporaryDirectory(prefix='economic-milestone-') as temp:
 out=Path(temp)
 studies={};provenance={}
 for name,run,job,sha,count in [('full',40201506480,121193471049,'45f844b055c10b82f7fcede4517bb273801234d9',29),('read',40201738305,121194333863,'5592fc14469e5c557325de28465f3d334a989cf7',3),('price',40202071064,121195155587,'66db91dff38e2be9549da352e67b859febabf7f3',2)]:
  studies[name],provenance[name]=read_run(run,job,sha,count)
 for file,data in [('verified-full-evidence.json.gz',studies),('verified-provenance.json.gz',provenance)]:
  with gzip.GzipFile(filename=str(out/file),mode='wb',mtime=0) as f:f.write(json.dumps(data,ensure_ascii=False,separators=(',',':')).encode())
 failed_logs=gh('api','--allow-escape-sequences',f'repos/{REPO}/actions/jobs/121189158855/logs')
 early=[json.loads(line.split('NETWORK_CASE ',1)[1]) for line in failed_logs.splitlines() if 'NETWORK_CASE ' in line]
 assert len(early)==13
 with gzip.GzipFile(filename=str(out/'pre-unit-correction-diagnostics.json.gz'),mode='wb',mtime=0) as f:f.write(json.dumps({'status':'FAILED_SCALE_FIXTURE_PRE_UNIT_CORRECTION_NOT_FINAL_CALIBRATION','source_sha':'236d3e18d26059a272ae4b0004ae62494d4c306c','run_url':f'https://github.com/{REPO}/actions/runs/40200061583','cases':early},ensure_ascii=False,separators=(',',':')).encode())
 # Only the four runtime changes; no experiment project, map or data archive.
 patch=subprocess.check_output(['git','diff',BASE,TARGET,'--','scripts/world/economy_r1_slice.gd','scripts/world/economy_slice_config.gd','scripts/world/economy_production_process.gd','scripts/world/economy_read_contract.gd'])
 (out/'formal-economy-minimal.patch').write_bytes(patch)
 def at_target(path):return subprocess.check_output(['git','show',TARGET+':'+path])
 contract=at_target('docs/ECONOMY_READ_CONTRACT_V1.md');report=at_target('docs/research/PRODUCTION_NETWORK_REPORT_20261025.md')
 (out/'ECONOMY_READ_CONTRACT_V1.md').write_bytes(contract)
 (out/'PRODUCTION_NETWORK_REPORT_20261025.md').write_bytes(report)
 readme=('最小只读交付；不复制实验工程，不自动修改主WWO，不启动本机Godot。\n'
 '补丁基准 '+BASE+'；交付 '+TARGET+'。\n'
 '仅四文件：economy_r1_slice、economy_slice_config、economy_production_process、economy_read_contract。\n'
 '原GUI从宿主认证上下文调用 economy.economy_read_view(authenticated_actor, firm_id, site_id)。\n'
 '禁止把用户输入actor字符串当认证身份；样本为内部企业操作者，不赋予玩家新权限。\n'
 '三个样本的源SHA/分钟/Actions在JSON中；order-rejected是请求未准入，不伪造已签订单违约。\n'
 '字段、单位、财务口径、未知成本和研究私态边界见接口合同。主工按其当前源码逐项审阅移植，禁止覆盖其他经济改动。\n'
 '本轮完成后停止，不自动优化下一轮，不通知其他工作线。\n')
 (out/'MINIMAL_HANDOFF.md').write_text(readme)
 with zipfile.ZipFile(out/'minimal-formal-handoff.zip','w',zipfile.ZIP_DEFLATED) as z:
  for name in ['formal-economy-minimal.patch','ECONOMY_READ_CONTRACT_V1.md','PRODUCTION_NETWORK_REPORT_20261025.md','MINIMAL_HANDOFF.md']:z.write(out/name,name)
  for name in ['normal.json','material-stop.json','order-rejected.json']:
   z.writestr('samples/'+name,at_target('docs/research/production-network/samples/'+name))
  z.writestr('NATIVE_PROOFS.json',at_target('docs/research/production-network/NATIVE_PROOFS.json'))
 runs=json.loads(gh('run','list','--repo',REPO,'--workflow','economy-cloud-check.yml','--limit','10','--json','databaseId,headSha,status,conclusion,url'))
 write(out/'workflow-runs.json',runs)
 manifest={'repository':REPO,'branch':'sandbox/main','baseline_sha':BASE,'delivery_sha':TARGET,'archive_run':os.environ['GITHUB_RUN_ID'],'economic_runs':{k:{'sha':v['sha'],'url':v['run_url'],'cases':len(v['cases'])} for k,v in studies.items()},'assets':{p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.iterdir())}}
 write(out/'ASSET_SHA256.json',manifest)
 notes=out.parent/(out.name+'-notes.md')
 notes.write_text('已完成的生产参数与20家Formal企业里程碑。\n\n交付提交 `'+TARGET+'`。29项完整对照、3个只读状态和2个真实采购成本对照均已通过；此作业只归档，不运行模拟。\n\n约18KB四文件运行时补丁、接口合同和三个真实样本在 minimal-formal-handoff.zip；完整压缩输出、来源hash和失败诊断分别保存，ASSET_SHA256.json给出校验。\n\n不包含地图、完整Godot工程或玩家存档，不自动应用到主WWO。历史校准、自然再生产、研发与完整净利润未建立。\n\n本轮停止，不开启下一轮、不通知其他工作线。')
 gh('release','create',TAG,*[str(p) for p in sorted(out.iterdir())],'--repo',REPO,'--target',TARGET,'--title','生产参数与20家企业Formal经济里程碑','--notes-file',str(notes),'--latest=false')
 published=json.loads(gh('release','view',TAG,'--repo',REPO,'--json','tagName,isDraft,assets,url'))
 assert not published['isDraft'] and len(published['assets'])==10
 print('ARCHIVE_VERIFIED '+json.dumps(published,ensure_ascii=False),flush=True)
 with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:f.write('Economic milestone archived: '+published['url']+'\n\nNo economic execution; all ten small assets verified.\n')
 notes.unlink()
