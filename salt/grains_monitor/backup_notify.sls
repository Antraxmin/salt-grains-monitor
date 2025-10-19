{% from "grains_monitor/map.jinja" import cfg with context %}

{% set region         = cfg.region %}
{% set phase          = cfg.phase %}
{% set git_repo_path  = cfg.git_repo_path %}
{% set dir_path       = git_repo_path ~ '/grains/' ~ region ~ '/' ~ phase %}
{% set grains_file    = dir_path ~ '/' ~ cfg.minion_id %}
{% set git_branch     = cfg.git_branch %}
{% set push_url       = cfg.push_url %}
{% set webhook_url    = cfg.webhook_url %}
{% set diff_max_chars = cfg.diff_max_chars %}
{% set github_repo    = cfg.github_repo %}
{% set git_user_name  = cfg.git_user_name %}
{% set git_user_email = cfg.git_user_email %}
{% set minion_id      = cfg.minion_id %}
{% set timestamp      = cfg.timestamp %}

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

create_region_phase_directory:
  file.directory:
    - name: {{ dir_path }}
    - makedirs: True
    - require:
      - cmd: init_git_repo

save_grains_file:
  file.managed:
    - name: {{ grains_file }}
    - contents_pillar: grains_content
    - makedirs: True
    - require:
      - file: create_region_phase_directory

git_prepare:
  cmd.run:
    - name: |
        set -e
        git config user.name {{ git_user_name|quote }}
        git config user.email {{ git_user_email|quote }}
        git add grains/{{ region|quote }}/{{ phase|quote }}/{{ minion_id|quote }}
    - cwd: {{ git_repo_path }}
    - require:
      - file: save_grains_file

commit_and_notify:
  cmd.run:
    - name: |
        set -e
        flock -w 30 /var/lock/grains-backup.lock bash -s <<'LOCKED_BLOCK'
        set -e

        build_commit_url() {
          local ch="$1" remote_url base_url owner_repo aux aux_san
          remote_url="$(git remote get-url origin 2>/dev/null || true)"
          if printf '%s' "$remote_url" | grep -qE '^https?://'; then
            remote_url="$(printf '%s' "$remote_url" | sed -E 's#^https?://[^@]+@#https://#')"
          fi
          if printf '%s' "$remote_url" | grep -qE '^git@github\.com:'; then
            owner_repo="${remote_url#git@github.com:}"; owner_repo="${owner_repo%.git}"
            base_url="https://github.com/${owner_repo}"
          elif printf '%s' "$remote_url" | grep -qE '^https?://github\.com/'; then
            owner_repo="${remote_url#https://github.com/}"; owner_repo="${owner_repo#http://github.com/}"
            owner_repo="${owner_repo%.git}"
            base_url="https://github.com/${owner_repo}"
          else
            aux="{{ github_repo }}"
            if [ -n "$aux" ]; then
              aux_san="$(printf '%s' "$aux" | sed -E 's#^https?://[^@]+@#https://#')"
              if printf '%s' "$aux_san" | grep -qE '^git@github\.com:'; then
                owner_repo="${aux_san#git@github.com:}"
              else
                owner_repo="${aux_san#https://github.com/}"; owner_repo="${owner_repo#http://github.com/}"
              fi
              owner_repo="${owner_repo%.git}"
              base_url="https://github.com/${owner_repo}"
            else
              base_url=""
            fi
          fi
          [ -n "$base_url" ] && [ -n "$ch" ] && printf '%s/commit/%s' "$base_url" "$ch" || printf ''
        }
        COMMIT_COUNT="$(git log --oneline -- grains/{{ region }}/{{ phase }}/{{ minion_id }} 2>/dev/null | wc -l || echo 0)"

        if [ "$COMMIT_COUNT" -gt 0 ]; then
          DIFF="$(
            git diff --no-color --cached --unified=0 -- grains/{{ region }}/{{ phase }}/{{ minion_id }} \
            | sed -n 's/^\([+-][^-+].*\)$/\1/p'
          )"
          if [ -n "$DIFF" ]; then
            git commit -m "Grains changed on {{ region }}/{{ phase }}/{{ minion_id }} at {{ timestamp }}"
            COMMIT_HASH="$(git rev-parse HEAD)"
            DIFF_TRUNCATED="$(printf "%s\n" "$DIFF" | head -c {{ diff_max_chars }})"
            COMMIT_URL="$(build_commit_url "$COMMIT_HASH")"
            if [ -n "{{ webhook_url }}" ]; then
              JSON_PAYLOAD="$(jq -n \
                --arg minion "{{ minion_id }}" \
                --arg url    "$COMMIT_URL" \
                --arg diff   "$DIFF_TRUNCATED" \
                '{
                   botName: $minion,
                   text: ("[변경 내역 확인하기(Git Repository)](" + $url + ")\n\n```diff\n" + $diff + "\n```")
                 }')"
              curl -sS -X POST {{ webhook_url|quote }} -H 'Content-Type: application/json' -d "$JSON_PAYLOAD" >/dev/null || true
            fi
          fi
        else
          git commit -m "Initial grains setup for {{ region }}/{{ phase }}/{{ minion_id }} at {{ timestamp }}"
          COMMIT_HASH="$(git rev-parse HEAD)"
          COMMIT_URL="$(build_commit_url "$COMMIT_HASH")"
          if [ -n "{{ webhook_url }}" ]; then
            JSON_PAYLOAD="$(jq -n \
              --arg minion "{{ minion_id }}" \
              --arg url    "$COMMIT_URL" \
              '{
                 botName: $minion,
                 text: ("[Grains initialized on " + $minion + "](" + $url + ")")
               }')"
            curl -sS -X POST {{ webhook_url|quote }} -H 'Content-Type: application/json' -d "$JSON_PAYLOAD" >/dev/null || true
          fi
        fi
        LOCKED_BLOCK
    - cwd: {{ git_repo_path }}
    - require:
      - cmd: git_prepare
