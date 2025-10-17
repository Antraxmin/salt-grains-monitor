{% set cfg = salt['pillar.get']('grains_monitor', {}) %}
{% set region         = cfg.get('region', 'test') %}
{% set phase          = cfg.get('phase',  'beta') %}
{% set git_repo_path  = cfg.get('git_repo_path', '/var/salt/grains-backup') %}
{% set webhook_url    = cfg.get('webhook_url', '') %}
{% set github_token   = cfg.get('github_token', '') %}
{% set github_repo    = cfg.get('github_repo', '') %}

{% set git_user_name  = cfg.get('git_user_name', 'Grains Monitor Bot') %}
{% set git_user_email = cfg.get('git_user_email', 'grains-monitor@example.local') %}
{% set git_branch     = cfg.get('git_branch', 'main') %}
{% set diff_max_chars = cfg.get('diff_max_chars', 800) %}

{% set minion_id      = salt['pillar.get']('minion_id', cfg.get('minion_id', 'unknown')) %}
{% set timestamp      = salt['pillar.get']('timestamp',  cfg.get('timestamp', '')) %}
{% set grains_content = salt['pillar.get']('grains_content', cfg.get('grains_content', '')) %}

{% set grains_file = git_repo_path ~ '/grains/' ~ minion_id %}

init_git_directory:
  file.directory:
    - name: {{ git_repo_path }}
    - makedirs: True

init_git_repo:
  cmd.run:
    - name: |
        if [ ! -d .git ]; then
          git init -b {{ git_branch }}
          if [ -n "{{ github_repo }}" ]; then
            git remote add origin {{ github_repo }}
          fi
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
        git config user.name "{{ git_user_name }}"
        git config user.email "{{ git_user_email }}"
        git add grains/{{ minion_id }}
    - cwd: {{ git_repo_path }}
    - require:
      - file: save_grains_file

commit_and_notify:
  cmd.run:
    - name: |
        COMMIT_COUNT=$(git log --oneline -- grains/{{ minion_id }} 2>/dev/null | wc -l)
        if [ "$COMMIT_COUNT" -gt 0 ]; then
          DIFF=$(git diff --no-color --cached --unified=0 -- grains/{{ minion_id }} \
                 | sed -n 's/^\([+-][^-+].*\)$/\1/p')
          if [ -n "$DIFF" ]; then
            git commit -m "Grains changed on {{ minion_id }} at {{ timestamp }}"
            COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")
            REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
            if printf '%s' "$REMOTE_URL" | grep -q '^git@github\.com:'; then
              OWNER_REPO=${REMOTE_URL#git@github.com:}; OWNER_REPO=${OWNER_REPO%.git}
              BASE_URL="https://github.com/$OWNER_REPO"
            elif printf '%s' "$REMOTE_URL" | grep -q '^https\?://github\.com/'; then
              OWNER_REPO=${REMOTE_URL#https://github.com/}; OWNER_REPO=${OWNER_REPO#http://github.com/}
              OWNER_REPO=${OWNER_REPO%.git}
              BASE_URL="https://github.com/$OWNER_REPO"
            else
              BASE_URL=""
            fi
            if [ -n "$BASE_URL" ] && [ -n "$COMMIT_HASH" ]; then
              COMMIT_URL="$BASE_URL/commit/$COMMIT_HASH"
            else
              COMMIT_URL=""
            fi
            git push https://{{ github_token }}@github.com/Antraxmin/grains-backup.git main
            DIFF_TRUNCATED=$(printf "%s\n" "$DIFF" | head -c {{ diff_max_chars }})
            JSON_PAYLOAD=$(jq -n \
              --arg minion "{{ minion_id }}" \
              --arg url    "$COMMIT_URL" \
              --arg diff   "$DIFF_TRUNCATED" \
              '{
                 botName: "{{ minion_id }}",
                 text: ("[변경 내역 확인하기(Git Repository)](" + $url + ")\n\n```diff\n" + $diff + "\n```")
               }')

            curl -sS -X POST '{{ webhook_url }}' \
              -H 'Content-Type: application/json' \
              -d "$JSON_PAYLOAD" >/dev/null
          fi
        else
          git commit -m "Initial grains setup for {{ minion_id }} at {{ timestamp }}"
          COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")
          REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
          if printf '%s' "$REMOTE_URL" | grep -q '^git@github\.com:'; then
            OWNER_REPO=${REMOTE_URL#git@github.com:}; OWNER_REPO=${OWNER_REPO%.git}
            BASE_URL="https://github.com/$OWNER_REPO"
          elif printf '%s' "$REMOTE_URL" | grep -q '^https\?://github\.com/'; then
            OWNER_REPO=${REMOTE_URL#https://github.com/}; OWNER_REPO=${OWNER_REPO#http://github.com/}
            OWNER_REPO=${OWNER_REPO%.git}
            BASE_URL="https://github.com/$OWNER_REPO"
          else
            BASE_URL=""
          fi
          if [ -n "$BASE_URL" ] && [ -n "$COMMIT_HASH" ]; then
            COMMIT_URL="$BASE_URL/commit/$COMMIT_HASH"
          else
            COMMIT_URL=""
          fi
          git push https://{{ github_token }}@github.com/Antraxmin/grains-backup.git {{ git_branch }}
          JSON_PAYLOAD=$(jq -n \
            --arg minion "{{ minion_id }}" \
            --arg url    "$COMMIT_URL" \
            '{
               botName: "{{ minion_id }}",
               text: ("[Grains monitoring initialized on " + $minion + "](" + $url + ")")
             }')

          curl -sS -X POST '{{ webhook_url }}' \
            -H 'Content-Type: application/json' \
            -d "$JSON_PAYLOAD" >/dev/null
        fi
    - cwd: {{ git_repo_path }}
    - require:
      - cmd: git_prepare
