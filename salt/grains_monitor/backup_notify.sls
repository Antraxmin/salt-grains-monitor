{% from "grains_monitor/map.jinja" import cfg with context %}

{% set git_repo_path   = cfg.git_repo_path %}
{% set grains_file     = cfg.git_repo_path ~ '/grains/' ~ cfg.minion_id %}
{% set git_branch      = cfg.git_branch %}
{% set push_url        = cfg.push_url %}
{% set webhook_url     = cfg.webhook_url %}
{% set diff_max_chars  = cfg.diff_max_chars %}
{% set github_repo     = cfg.github_repo %}
{% set git_user_name   = cfg.git_user_name %}
{% set git_user_email  = cfg.git_user_email %}
{% set minion_id       = cfg.minion_id %}
{% set timestamp       = cfg.timestamp %}

init_git_directory:
  file.directory:
    - name: {{ git_repo_path }}
    - makedirs: True

init_git_repo:
  cmd.run:
    - name: |
        set -e
        if [ ! -d .git ]; then
          git init -b {{ git_branch|quote }}
          if [ -n "{{ github_repo }}" ]; then
            git remote add origin {{ github_repo|quote }}
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
        set -e
        git config user.name {{ git_user_name|quote }}
        git config user.email {{ git_user_email|quote }}
        git add grains/{{ minion_id|quote }}
    - cwd: {{ git_repo_path }}
    - require:
      - file: save_grains_file

commit_and_notify:
  cmd.run:
    - name: |
        set -e

        COMMIT_COUNT=$(git log --oneline -- grains/{{ minion_id }} 2>/dev/null | wc -l || echo 0)
        if [ "$COMMIT_COUNT" -gt 0 ]; then
          DIFF=$(
            git diff --no-color --cached --unified=0 -- grains/{{ minion_id }} \
            | sed -n 's/^\([+-][^-+].*\)$/\1/p'
          )
          if [ -n "$DIFF" ]; then
            git commit -m "Grains changed on {{ minion_id }} at {{ timestamp }}"
            COMMIT_HASH=$(git rev-parse HEAD)
            {% if push_url %}
            git push {{ push_url|quote }} {{ git_branch|quote }}
            {% else %}
            git push origin {{ git_branch|quote }}
            {% endif %}
            DIFF_TRUNCATED=$(printf "%s\n" "$DIFF" | head -c {{ diff_max_chars }})
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
            [ -n "$BASE_URL" ] && COMMIT_URL="$BASE_URL/commit/$COMMIT_HASH" || COMMIT_URL=""

            JSON_PAYLOAD=$(jq -n \
              --arg minion "{{ minion_id }}" \
              --arg url    "$COMMIT_URL" \
              --arg diff   "$DIFF_TRUNCATED" \
              '{
                 botName: $minion,
                 text: ("[변경 내역 확인하기(Git Repository)](" + $url + ")\n\n```diff\n" + $diff + "\n```")
               }')

            if [ -n "{{ webhook_url }}" ]; then
              curl -sS -X POST {{ webhook_url|quote }} \
                   -H 'Content-Type: application/json' \
                   -d "$JSON_PAYLOAD" >/dev/null
            fi
          fi
        else
          git commit -m "Initial grains setup for {{ minion_id }} at {{ timestamp }}"
          COMMIT_HASH=$(git rev-parse HEAD)

          {% if push_url %}
          git push {{ push_url|quote }} {{ git_branch|quote }}
          {% else %}
          git push origin {{ git_branch|quote }}
          {% endif %}

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
          [ -n "$BASE_URL" ] && COMMIT_URL="$BASE_URL/commit/$COMMIT_HASH" || COMMIT_URL=""
          if [ -n "{{ webhook_url }}" ]; then
            JSON_PAYLOAD=$(jq -n \
              --arg minion "{{ minion_id }}" \
              --arg url    "$COMMIT_URL" \
              '{
                 botName: $minion,
                 text: ("[Grains monitoring initialized on " + $minion + "](" + $url + ")")
               }')
            curl -sS -X POST {{ webhook_url|quote }} \
                 -H 'Content-Type: application/json' \
                 -d "$JSON_PAYLOAD" >/dev/null
          fi
        fi
    - cwd: {{ git_repo_path }}
    - require:
      - cmd: git_prepare
