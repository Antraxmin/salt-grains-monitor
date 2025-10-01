{% set minion_id = salt['pillar.get']('minion_id', 'unknown') %}
{% set timestamp = salt['pillar.get']('timestamp', '') %}
{% set grains_content = salt['pillar.get']('grains_content', '') %}
{% set git_repo_path = '/var/salt/grains-backup' %}
{% set grains_file = git_repo_path ~ '/grains/' ~ minion_id ~ '.txt' %}
{% set webhook_url = 'https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA' %}

init_git_directory:
  file.directory:
    - name: {{ git_repo_path }}
    - makedirs: True

init_git_repo:
  cmd.run:
    - name: git init
    - cwd: {{ git_repo_path }}
    - unless: test -d {{ git_repo_path }}/.git
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
        git config user.name "Antraxmin" || true
        git config user.email "antraxmin@naver.com" || true
        git add grains/{{ minion_id }}.txt
    - cwd: {{ git_repo_path }}
    - require:
      - file: save_grains_file

extract_changes_only:
  cmd.run:
    - name: |
        git diff --cached --unified=0 grains/{{ minion_id }}.txt | \
        grep -E '^(\+[^+]|-[^-])' > /tmp/grains_changes_{{ minion_id }}.txt || echo "No changes" > /tmp/grains_changes_{{ minion_id }}.txt
    - cwd: {{ git_repo_path }}
    - require:
      - cmd: git_prepare

{% set filtered_diff = salt['cmd.run']('cat /tmp/grains_changes_' ~ minion_id ~ '.txt') %}

{% if filtered_diff and filtered_diff != 'No changes' %}

commit_grains_changes:
  cmd.run:
    - name: git commit -m "Grains changed on {{ minion_id }} at {{ timestamp }}"
    - cwd: {{ git_repo_path }}
    - require:
      - cmd: extract_changes_only

send_dooray_notification:
  cmd.run:
    - name: |
        DIFF=$(cat /tmp/grains_changes_{{ minion_id }}.txt 2>/dev/null | head -c 800)
        JSON_PAYLOAD=$(jq -n \
          --arg minion "{{ minion_id }}" \
          --arg time "{{ timestamp }}" \
          --arg diff "$DIFF" \
          --arg repo "{{ git_repo_path }}" \
          '{botName: "Grains Monitor", text: "[Grains 변경 알림]\n\nMinion: \($minion)\n변경 시간: \($time)\n\n변경 내용:\n```diff\n\($diff)\n```\n\nGit Repo: \($repo)"}')
        curl -X POST '{{ webhook_url }}' \
          -H 'Content-Type: application/json' \
          -d "$JSON_PAYLOAD"
    - require:
      - cmd: commit_grains_changes

cleanup_temp_file:
  file.absent:
    - name: /tmp/grains_changes_{{ minion_id }}.txt
    - require:
      - cmd: send_dooray_notification

{% else %}

log_no_changes:
  test.succeed_without_changes:
    - name: No changes detected in grains for {{ minion_id }}

cleanup_empty_file:
  file.absent:
    - name: /tmp/grains_changes_{{ minion_id }}.txt

{% endif %}