{% set minion_id = salt['pillar.get']('minion_id', 'unknown') %}
{% set timestamp = salt['pillar.get']('timestamp', '') %}
{% set grains_content = salt['pillar.get']('grains_content', '') %}
{% set git_repo_path = '/var/salt/grains-backup' %}
{% set grains_file = git_repo_path ~ '/grains/' ~ minion_id ~ '.txt' %}
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
        git add grains/{{ minion_id }}.txt
    - cwd: {{ git_repo_path }}
    - require:
      - file: save_grains_file

commit_and_notify:
  cmd.run:
    - name: |
        COMMIT_COUNT=$(git log --oneline -- grains/{{ minion_id }}.txt 2>/dev/null | wc -l)
        if [ "$COMMIT_COUNT" -gt 0 ]; then
          DIFF=$(git diff --cached --unified=0 grains/{{ minion_id }}.txt | grep -E '^(\+[^+]|-[^-])' || echo "")
          if [ -n "$DIFF" ]; then
            git commit -m "Grains changed on {{ minion_id }} at {{ timestamp }}"
            git push https://{{ github_token }}@github.com/Antraxmin/grains-backup.git main
            DIFF_TRUNCATED=$(echo "$DIFF" | head -c 800)
            JSON_PAYLOAD=$(jq -n \
              --arg minion "{{ minion_id }}" \
              --arg time "{{ timestamp }}" \
              --arg diff "$DIFF_TRUNCATED" \
              --arg repo "{{ git_repo_path }}" \
              '{botName: "Grains Monitor", text: ("Grains 변경 알림 (" + $minion + ")\n\n```diff\n" + $diff + "\n```")}')
            curl -X POST '{{ webhook_url }}' \
              -H 'Content-Type: application/json' \
              -d "$JSON_PAYLOAD"
          fi
        else
          git commit -m "Initial grains setup for {{ minion_id }} at {{ timestamp }}"
          git push https://{{ github_token }}@github.com/Antraxmin/grains-backup.git main
          JSON_PAYLOAD=$(jq -n \
            --arg minion "{{ minion_id }}" \
            --arg time "{{ timestamp }}" \
            --arg repo "{{ git_repo_path }}" \
            '{
              botName: "Grains Monitor",
              attachments: [
                {
                  title: ("$minion + " 연동 완료"),
                  text: ("\n" + $minion + " 서버의 Grains 모니터링이 정상적으로 시작되었습니다."),
                  color: "green"
                }
              ]
            }')
          curl -X POST '{{ webhook_url }}' \
            -H 'Content-Type: application/json' \
            -d "$JSON_PAYLOAD"
        fi
    - cwd: {{ git_repo_path }}
    - require:
      - cmd: git_prepare