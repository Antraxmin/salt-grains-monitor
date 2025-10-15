{% set minion_id = salt['pillar.get']('minion_id', 'unknown') %}
{% set timestamp = salt['pillar.get']('timestamp', '') %}
{% set grains_content = salt['pillar.get']('grains_content', '') %}
{% set git_repo_path = '/var/salt/grains-backup' %}
{% set grains_file = git_repo_path ~ '/grains/' ~ minion_id %}
{% set webhook_url = 'https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA' %}
{% set github_token = salt['pillar.get']('grains_monitor:github_token', '') %}
{% set github_repo = salt['pillar.get']('grains_monitor:github_repo', '') %}

init_git_directory:
  file.directory:
    - name: {{ git_repo_path }}
    - makedirs: True

init_git_repo:
  cmd.run:
    - name: |
        if [ ! -d .git ]; then
          git init -b main
          git remote add origin {{ github_repo }}
        fi
    - cwd: {{ git_repo_path }}
    - require:
      - file: init_git_directory

create_grains_directory:
  file.directory:
    - name: {{ git_repo_path }}/grains
    - makedirs: True
    - require:
      - cmd: init_git_repo

save_grains_file:
  file.managed:
    - name: {{ grains_file }}
    - contents_pillar: grains_content
    - makedirs: True
    - require:
      - file: create_grains_directory

git_prepare:
  cmd.run:
    - name: |
        git config user.name "Antraxmin"
        git config user.email "antraxmin@naver.com"
        git add grains/{{ minion_id }}
    - cwd: {{ git_repo_path }}
    - require:
      - file: save_grains_file

commit_and_notify:
  cmd.run:
    - name: |
        set -u
        LOG=/tmp/grains-monitor.log
        {
          echo "===== $(date '+%F %T') start ====="
          echo "CWD=$(pwd)"
          echo "git version: $(git --version 2>&1)"

          COMMIT_COUNT=$(git log --oneline -- grains/{{ minion_id }} 2>/dev/null | wc -l | tr -d ' ')
          echo "COMMIT_COUNT=$COMMIT_COUNT (file=grains/{{ minion_id }})"

          if [ "$COMMIT_COUNT" -gt 0 ]; then
            echo "[path] incremental-change"
            git status --porcelain
            git diff --name-only --cached -- grains/{{ minion_id }}
            DIFF=$(git diff --no-color --cached --unified=0 -- grains/{{ minion_id }} \
                   | sed -n 's/^\([+-][^-+].*\)$/\1/p')
            echo "DIFF_LEN=$(printf '%s' "$DIFF" | wc -c | tr -d ' ')"
            printf "%s\n" "$DIFF" > /tmp/gm_diff.txt

            if [ -n "$DIFF" ]; then
              echo "[do] commit+push+webhook (incremental)"
              git config user.name "Antraxmin"
              git config user.email "antraxmin@naver.com"
              git commit -m "Grains changed on {{ minion_id }} at {{ timestamp }}"
              echo "[git] pushing..."
              git push https://{{ github_token }}@github.com/Antraxmin/grains-backup.git main 2>&1 | tee /tmp/gm_gitpush.txt

              DIFF_TRUNCATED=$(printf "%s\n" "$DIFF" | head -c 800)
              JSON_PAYLOAD=$(jq -n \
                --arg minion "{{ minion_id }}" \
                --arg time "{{ timestamp }}" \
                --arg diff "$DIFF_TRUNCATED" \
                '{botName: "Grains Monitor", text: ("Grains 변경 알림 (" + $minion + ")\n\n" + $diff)}')
              echo "$JSON_PAYLOAD" | jq . >/tmp/dooray_payload.json 2>/dev/null || echo "$JSON_PAYLOAD" >/tmp/dooray_payload.json

              HTTP_CODE=$(curl -sS -o /tmp/dooray_resp.txt -w "%{http_code}" \
                -H 'Content-Type: application/json' -X POST '{{ webhook_url }}' -d "$JSON_PAYLOAD")
              echo "Dooray HTTP: $HTTP_CODE"
              [ "$HTTP_CODE" = "200" ] || sed -n '1,200p' /tmp/dooray_resp.txt
            else
              echo "[skip] no staged diff"
            fi
          else
            echo "[path] first-time setup"
            git config user.name "Antraxmin"
            git config user.email "antraxmin@naver.com"
            echo "[git] status before first commit:"
            git status --porcelain
            git log --oneline -- grains/{{ minion_id }} 2>/dev/null | wc -l

            git commit -m "Initial grains setup for {{ minion_id }} at {{ timestamp }}"
            echo "[git] pushing (first commit)..."
            git push https://{{ github_token }}@github.com/Antraxmin/grains-backup.git main 2>&1 | tee /tmp/gm_gitpush.txt

            JSON_PAYLOAD=$(jq -n \
              --arg minion "{{ minion_id }}" \
              --arg time "{{ timestamp }}" \
              '{botName: "Grains Monitor", text: ($minion + " 서버의 Grains 모니터링이 정상적으로 시작되었습니다.\n\n" + $time)}')
            echo "$JSON_PAYLOAD" | jq . >/tmp/dooray_payload.json 2>/dev/null || echo "$JSON_PAYLOAD" >/tmp/dooray_payload.json

            HTTP_CODE=$(curl -sS -o /tmp/dooray_resp.txt -w "%{http_code}" \
              -H 'Content-Type: application/json' -X POST '{{ webhook_url }}' -d "$JSON_PAYLOAD")
            echo "Dooray HTTP: $HTTP_CODE"
            [ "$HTTP_CODE" = "200" ] || sed -n '1,200p' /tmp/dooray_resp.txt
          fi

          echo "===== end ====="
        } >>"$LOG" 2>&1
    - cwd: {{ git_repo_path }}
    - require:
      - cmd: git_prepare