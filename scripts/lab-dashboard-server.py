#!/usr/bin/env python3
"""Local, allow-listed command runner for the GitLab learning dashboard."""
from __future__ import annotations
import hmac, json, os, secrets, subprocess, sys, threading, time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
PAGE, GUIDE = ROOT / "lab-progress.html", ROOT / "compose-actions.md"
PORT = int(os.environ.get("LAB_DASHBOARD_PORT", "8090"))
TOKEN, JOBS, LOCK = secrets.token_urlsafe(32), {}, threading.Lock()

# No command comes from the browser. This is the complete command allow-list.
ACTIONS = {
 "clear-lab": ("Clear the current GitLab instance", [["bash","-lc",'''podman stop -a && podman rm -a && \
podman rmi -f otus-gitlab-runner:local
podman ps -a
rm -rf ./local/gitlab ./local/runner ./local/gitlab-root-password.env ./projects/cocktail-search/.git''']]),
 "initialize": ("Initialize local credentials", [["./scripts/initialize-gitlab.sh"]]),
 "start-gitlab": ("Start GitLab CE", [["podman","compose","up","-d","gitlab"]]),
 "wait-gitlab": ("Wait for GitLab readiness", [["python3","-c",'''import sys,time,urllib.request
for attempt in range(1,21):
 try:
  response=urllib.request.urlopen("http://localhost:8929/users/sign_in",timeout=10)
  print(f"GitLab is ready (HTTP {response.status})."); sys.exit(0)
 except Exception as error: print(f"Attempt {attempt}/20: not ready ({error}).",flush=True); time.sleep(30)
sys.exit("GitLab did not become ready within 10 minutes.")''']]),
 "start-runner": ("Build and start Runner", [["podman","compose","build","runner"],["podman","compose","up","-d","runner"],["podman","compose","exec","runner","docker","info"],["podman","compose","exec","runner","gitlab-runner","--version"]]),
 "register-runner": ("Register group Runner", [["./scripts/register-group-runner.sh"],["podman","compose","exec","runner","gitlab-runner","verify"]]),
 "configure-ssh": ("Configure SSH trust and identity", [["./scripts/trust-local-gitlab-host-key.sh"],["./scripts/add-user-ssh-key.sh"],["bash","-lc",'ssh -o StrictHostKeyChecking=yes -p 2222 -T git@localhost; status=$?; test "$status" -eq 1 -o "$status" -eq 0']]),
 "create-project": ("Publish tracked application source", [["bash","-lc",'''set -e
./scripts/create-cocktail-search-project.sh
cd projects/cocktail-search
git init --initial-branch=main
git add .
git commit -m "Publish application to local GitLab"
git remote add origin ssh://git@localhost:2222/gulash-prj/cocktail-search.git
git push -u origin main''']]),
 "show-login-password": ("Show GitLab sign-in password", [["bash","-lc",'''curl -fsS http://localhost:8929/users/sign_in >/dev/null && \
{ echo "it's ok" && grep '^GITLAB_ROOT_PASSWORD=' local/gitlab-root-password.env; } || \
echo "not yet"''']]),
 "launch-all": ("Launch the complete learning lab", []),
}
LAUNCH_ORDER = ["clear-lab", "initialize", "start-gitlab", "wait-gitlab", "start-runner", "register-runner", "configure-ssh", "create-project"]

def run_job(job_id, action_id):
 def append(text):
  with LOCK: JOBS[job_id]["log"]=(JOBS[job_id]["log"]+text.replace("BOOTSTRAP_TOKEN=","BOOTSTRAP_TOKEN=[redacted]"))[-100000:]
 try:
  action_ids=LAUNCH_ORDER if action_id=="launch-all" else [action_id]
  for current_action in action_ids:
   append("\n== "+ACTIONS[current_action][0]+" ==\n")
   for command in ACTIONS[current_action][1]:
    append("\n$ "+" ".join(command)+"\n")
    process=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
    for line in process.stdout: append(line)
    if process.wait(): raise RuntimeError(f"Command exited with status {process.returncode}.")
   with LOCK: JOBS[job_id]["completed_actions"].append(current_action)
  with LOCK: JOBS[job_id]["state"]="succeeded"
 except Exception as error:
  append(f"\nERROR: {error}\n")
  with LOCK: JOBS[job_id]["state"]="failed"

class Handler(BaseHTTPRequestHandler):
 def log_message(self, fmt, *args): sys.stderr.write("dashboard: "+fmt%args+"\n")
 def json(self,status,payload):
  body=json.dumps(payload).encode(); self.send_response(status); self.send_header("Content-Type","application/json; charset=utf-8"); self.send_header("Cache-Control","no-store"); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
 def authorized(self):
  origin=self.headers.get("Origin"); expected=f"http://127.0.0.1:{PORT}"
  if origin and origin != expected: self.json(HTTPStatus.FORBIDDEN,{"error":"Unexpected browser origin."}); return False
  if not hmac.compare_digest(self.headers.get("X-Lab-Token",""),TOKEN): self.json(HTTPStatus.UNAUTHORIZED,{"error":"Open the tokenized URL printed by the starter script."}); return False
  return True
 def do_GET(self):
  request=urlparse(self.path)
  if request.path=="/api/jobs":
   if not self.authorized(): return
   job_id=parse_qs(request.query).get("id",[""])[0]
   with LOCK: job=dict(JOBS[job_id]) if job_id in JOBS else None
   return self.json(HTTPStatus.OK,job) if job else self.json(HTTPStatus.NOT_FOUND,{"error":"Unknown job."})
  static={"/":(PAGE,"text/html; charset=utf-8"),"/lab-progress.html":(PAGE,"text/html; charset=utf-8"),"/compose-actions.md":(GUIDE,"text/markdown; charset=utf-8"),"/steps/02_create-cocktail-search-gitlab-project/README.md":(ROOT/"steps/02_create-cocktail-search-gitlab-project/README.md","text/markdown; charset=utf-8")}.get(request.path)
  if not static: return self.send_error(HTTPStatus.NOT_FOUND,"Only dashboard files are served.")
  body=static[0].read_bytes(); self.send_response(HTTPStatus.OK); self.send_header("Content-Type",static[1]); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
 def do_POST(self):
  action=urlparse(self.path).path.removeprefix("/api/actions/")
  if action not in ACTIONS: return self.json(HTTPStatus.NOT_FOUND,{"error":"Unknown action."})
  if not self.authorized(): return
  job_id=secrets.token_urlsafe(12)
  with LOCK: JOBS[job_id]={"id":job_id,"action":action,"label":ACTIONS[action][0],"state":"running","log":"Queued.\n","completed_actions":[],"started_at":time.time()}
  threading.Thread(target=run_job,args=(job_id,action),daemon=True).start()
  self.json(HTTPStatus.ACCEPTED,{"id":job_id})

if __name__=="__main__":
 if not PAGE.is_file() or not GUIDE.is_file(): raise SystemExit("Run from the checked-out learning-lab repository.")
 if not 1<=PORT<=65535: raise SystemExit("LAB_DASHBOARD_PORT must be between 1 and 65535.")
 server=ThreadingHTTPServer(("127.0.0.1",PORT),Handler)
 print("GitLab learning dashboard is running locally.")
 print(f"Open: http://127.0.0.1:{PORT}/?token={TOKEN}")
 print("Press Ctrl-C to stop it. It accepts only documented dashboard actions.")
 try: server.serve_forever()
 except KeyboardInterrupt: print("\nDashboard stopped.")
 finally: server.server_close()
