{# ===============================
# orch/grains_push_orch.sls
#  - 배치마다 Dooray 알림 1건 전송
#  - grains/*/*/* 경로만 집계
#  - last_ref/last_ts 관리로 증분 처리
# =============================== #}

{# ---- Pillar ---- #}
{% set C       = salt['pillar.get']('grains_monitor', {}) %}
{% set repo    = C.get('git_repo_path', '/var/salt/grains-backup') %}
{% set branch  = C.get('git_branch', 'main') %}

{# github_https_base 없으면 github_repo에서 .git만 떼고 사용 (중첩 if 제거) #}
{% set gh = (C.get('github_https_base', '') or C.get('github_repo', ''))|replace('.git','') %}

{# Dooray(또는 일반 웹훅) URL: dooray_webhook_url -> webhook_url 우선순위 #}
{% set wh = C.get('dooray_webhook_url', C.get('webhook_url', '')) %}

{% set P       = C.get('push', {}) %}
{% set minc    = P.get('min_commits', 1) %}
{% set maxage  = P.get('max_age', 300) %}
{% set maxcomm = P.get('max_commits_per_batch', 50) %}
{% set diffmax = P.get('diff_max_chars', C.get('diff_max_chars', 2000)) %}

{# ---- State files ---- #}
{% set state_dir  = '/var/lib/salt-grains-monitor' %}
{% set last_ref_f = state_dir + '/last_ref' %}
{% set last_ts_f  = state_dir + '/last_ts' %}

{# ---- 공통 준비 ---- #}
ensure-state-dir:
  salt.function:
    - name: file.mkdir
    - tgt: 'salt-master'
    - kwarg: { dir_path: {{ state_dir }} }

git-fetch:
  salt.function:
    - name: git.fetch
    - tgt: 'salt-master'
    - kwarg: { cwd: {{ repo }}, remote: 'origin' }
    - require:
      - salt: ensure-state-dir

remote-head:
  salt.function:
    - name: git.rev_parse
    - tgt: 'salt-master'
    - kwarg: { cwd: {{ repo }}, rev: 'origin/{{ branch }}' }
    - require:
      - salt: git-fetch

calc-to-push:
  salt.function:
    - name: cmd.run_stdout
    - tgt: 'salt-master'
    - kwarg:
        cmd: "git -C {{ repo }} rev-list --count origin/{{ branch }}..HEAD || echo 0"
        python_shell: True
    - require:
      - salt: remote-head

read-last-ref:
  salt.function:
    - name: file.file_exists
    - tgt: 'salt-master'
    - kwarg: { path: {{ last_ref_f }} }

get-last-ref:
  salt.function:
    - name: file.read
    - tgt: 'salt-master'
    - kwarg: { path: {{ last_ref_f }} }
    - onlyif:
      - salt: read-last-ref

read-last-ts:
  salt.function:
    - name: file.file_exists
    - tgt: 'salt-master'
    - kwarg: { path: {{ last_ts_f }} }

get-last-ts:
  salt.function:
    - name: file.read
    - tgt: 'salt-master'
    - kwarg: { path: {{ last_ts_f }} }
    - onlyif:
      - salt: read-last-ts

{# ---- Jinja 계산 (증분 기준/조건) ---- #}
{% set base_ref = (salt['file.read'](last_ref_f).strip() if salt['file.file_exists'](last_ref_f) else 'origin/' + branch) %}
{% set last_ts  = (salt['file.read'](last_ts_f).strip() if salt['file.file_exists'](last_ts_f) else '0')|int %}
{% set now_ts   = salt['cmd.run_stdout']('date +%s')|int %}
{% set age      = now_ts - last_ts %}
{% set to_push  = (salt['cmd.run_stdout']('git -C {} rev-list --count origin/{}..HEAD || echo 0'.format(repo, branch)) or '0')|int %}
{% set do_push  = (to_push >= minc) or (age >= maxage) %}
{% set have_wh  = (wh|length) > 0 %}

{% if do_push %}

pull-rebase:
  salt.function:
    - name: cmd.run
    - tgt: 'salt-master'
    - kwarg:
        cmd: "git -C {{ repo }} pull --rebase --autostash origin {{ branch }} || true"
        python_shell: True
    - require:
      - salt: git-fetch

push-origin:
  salt.function:
    - name: git.push
    - tgt: 'salt-master'
    - kwarg: { cwd: {{ repo }}, remote: 'origin', ref: {{ branch }} }
    - require:
      - salt: pull-rebase

new-head:
  salt.function:
    - name: git.rev_parse
    - tgt: 'salt-master'
    - kwarg: { cwd: {{ repo }}, rev: 'HEAD' }
    - require:
      - salt: push-origin

collect-commits:
  salt.function:
    - name: cmd.run_stdout
    - tgt: 'salt-master'
    - kwarg:
        cmd: "git -C {{ repo }} log --no-merges --pretty='%H|%s' --reverse {{ base_ref }}..HEAD -- 'grains/*/*/*' || true"
        python_shell: True
    - require:
      - salt: new-head

{# ---- 배치 1건 Dooray 알림 ---- #}
{% if have_wh %}
dooray-notify-batch:
  salt.function:
    - name: cmd.run
    - tgt: 'salt-master'
    - kwarg:
        shell: /bin/bash
        python_shell: True
        cmd: |
          set -euo pipefail
          exec 1> >(tee -a /var/log/grains-dooray.log) 2>&1
          set -x

          WH='{{ wh|replace("'", "'\\''") }}'
          REPO='{{ repo|replace("'", "'\\''") }}'
          BR='{{ branch|replace("'", "'\\''") }}'
          GH='{{ gh|replace("'", "'\\''") }}'
          LAST_REF_FILE='{{ last_ref_f }}'
          MAXCOMM={{ maxcomm }}
          DIFFMAX={{ diffmax }}

          if [ -z "$WH" ]; then
            echo "[dooray] webhook empty; skip"
            exit 0
          fi

          if [ -s "$LAST_REF_FILE" ]; then
            BASE_REF="$(tr -d '\n' < "$LAST_REF_FILE")"
          else
            BASE_REF="origin/{{ branch }}"
          fi
          echo "[dooray] BASE_REF=$BASE_REF"

          mapfile -t ROWS < <(git -C "$REPO" log --no-merges --pretty='%H|%s' --reverse "$BASE_REF"..HEAD -- 'grains/*/*/*' | head -n "$MAXCOMM")
          CNT="${#ROWS[@]}"
          echo "[dooray] batch commits: $CNT"
          if [ "$CNT" -eq 0 ]; then
            echo "[dooray] no commits to notify"
            exit 0
          fi

          LIST_MD=""
          SCOPES_SET=""
          for row in "${ROWS[@]}"; do
            h="${row%%|*}"
            subj="${row#*|}"

            scope="$(git -C "$REPO" diff-tree --no-commit-id --name-only -r "$h" -- 'grains/*/*/*' \
              | awk -F/ '/^grains\/[^\/]+\/[^\/]+\/[^\/]+$/ {print $2"/"$3":"$4}' \
              | sort -u | paste -sd ', ' -)"
            [ -z "$scope" ] && scope="unknown"

            if [ -n "$GH" ]; then
              LIST_MD+=$'- [`'"${h:0:7}"'`]('"$GH"'/commit/'"$h"$') **'"$subj"$'** — '"$scope"$'\n'
            else
              LIST_MD+=$'- `'"${h:0:7}"'` **'"$subj"$'** — '"$scope"$'\n'
            fi

            SCOPES_SET+="${scope}, "
          done

          SCOPES_SUM="${SCOPES_SET%, }"
          [ -z "$SCOPES_SUM" ] && SCOPES_SUM="unknown"

          DIFF_TXT="$(git -C "$REPO" diff --no-color --unified=0 "$BASE_REF"..HEAD -- 'grains/*/*/*' \
            | sed -n 's/^[+-][^-+].*$/\0/p' | head -c "$DIFFMAX")"

          HEADER="**Pushed ${CNT} commit(s) to ${BR}**"
          COMPARE_LINE=""
          if [ -n "$GH" ]; then
            COMPARE_LINE=$'\n\nCompare: '"$GH"'/compare/'"${BASE_REF##*/}"'...HEAD'
          fi

          TEXT="${HEADER}"$'\n\n'"${LIST_MD}""${COMPARE_LINE}"
          if [ -n "$DIFF_TXT" ]; then
            TEXT+=$'\n\n```diff\n'"${DIFF_TXT}"$'\n```'
          fi

          BOT="grains-batch (${SCOPES_SUM})"

          echo "[dooray] POST $WH :: $BOT :: $CNT commits"

          python3 - "$WH" "$BOT" "$TEXT" <<'PY'
import json, sys, urllib.request, ssl
url, bot, text = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.dumps({"botName": bot, "text": text}).encode("utf-8")
ctx = ssl.create_default_context()
req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=15, context=ctx) as r:
        body = r.read(300).decode(errors="ignore")
        print(f"[dooray] RESP {r.status} {body}")
except Exception as e:
    print(f"[dooray] ERR {e}", file=sys.stderr)
PY
    - require:
      - salt: new-head
{% endif %}

{# ---- 상태 갱신(last_ref/last_ts) ---- #}
write-last-ref:
  salt.function:
    - name: file.write
    - tgt: 'salt-master'
    - kwarg:
        path: {{ last_ref_f }}
        contents: {{ salt['cmd.run_stdout']('git -C {} rev-parse HEAD'.format(repo)).strip() }}
    - require:
      - salt: new-head

write-last-ts:
  salt.function:
    - name: file.write
    - tgt: 'salt-master'
    - kwarg:
        path: {{ last_ts_f }}
        contents: {{ now_ts }}
    - require:
      - salt: new-head

{% else %}

noop-no-push:
  test.nop:
    - name: "No push (to_push={{ to_push }}, age={{ age }}s; min_commits={{ minc }}, max_age={{ maxage }})"

{% endif %}


