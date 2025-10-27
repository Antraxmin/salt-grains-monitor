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
        fi
        git config user.name {{ git_user_name|quote }}
        git config user.email {{ git_user_email|quote }}
        if ! git remote | grep -q origin && [ -n "{{ github_repo }}" ]; then
          git remote add origin {{ github_repo|quote }}
        fi
    - cwd: {{ git_repo_path }}
    - require:
      - file: init_git_directory

save_grains_file:
  file.managed:
    - name: {{ grains_file }}
    - contents_pillar: grains_content
    - makedirs: True
    - require:
      - cmd: init_git_repo

git_prepare:
  cmd.run:
    - name: git add grains/{{ region }}/{{ phase }}/{{ minion_id }}
    - cwd: {{ git_repo_path }}
    - require:
      - file: save_grains_file

commit_and_notify:
  cmd.run:
    - name: |
        BASE_URL="{{ github_repo | replace('.git', '') }}"
        
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
            COMMIT_URL="${BASE_URL}/commit/${COMMIT_HASH}"
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
          COMMIT_URL="${BASE_URL}/commit/${COMMIT_HASH}"
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

    - cwd: {{ git_repo_path }}
    - require:
      - cmd: git_prepare
