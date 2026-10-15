"""Reuse original framed Connection methods with a sandbox observation host."""
import json
from pathlib import Path
import queue
import subprocess
import threading


def connect(module, root, scenario, godot):
    class ResearchConnection(module.Connection):
        def __init__(self):
            self.sid='sandbox_session'; self.seq=0; self.capture=False; self.packets=[]
            self.responses=queue.Queue(maxsize=4); self.raw_diagnostics=[]
            self.diagnostic_bytes=0; self.diagnostic_dropped=0; self.closed_record=None
            self.last_program={}; self.costs={'io_seconds':0.0,'format_seconds':0.0}
            script=Path(__file__).with_name('research_observer.gd')
            self.proc=subprocess.Popen([godot,'--headless','--path',str(root),'--script',str(script),'--',
                json.dumps({'seed':scenario['seed'],'quota':scenario['params']['quota']})],cwd=root,
                stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            self.reader=threading.Thread(target=self._read,daemon=True); self.reader.start()
            try:
                self.start=self.receive(20)
                if not self.start.get('started'):raise RuntimeError('research_host_start_failed')
            except BaseException:
                self.abort(); raise
    return ResearchConnection()
