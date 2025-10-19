import subprocess, shlex

def _sh(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, shell=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def push(repo, branch="main", remote="origin"):
    ahead = _sh(f"git rev-list --left-only --count {remote}/{branch}...HEAD", cwd=repo)
    if ahead.returncode != 0:
        _sh(f"git fetch {remote} {branch}", cwd=repo)
        ahead = _sh(f"git rev-list --left-only --count {remote}/{branch}...HEAD", cwd=repo)

    try_push = _sh(f"git push {remote} {branch}", cwd=repo)
    if try_push.returncode == 0:
        return {"result": True, "pushed": True, "ahead": ahead.stdout.strip()}
    return {"result": False, "pushed": False, "stderr": try_push.stderr}
