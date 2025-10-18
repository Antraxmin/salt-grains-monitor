{% from "grains_monitor/map.jinja" import cfg with context %}

{% set git_repo_path = cfg.git_repo_path %}
{% set grains_dir    = cfg.grains_dir %}
{% set grains_file   = cfg.grains_file %}
{% set git_branch    = cfg.git_branch %}
{% set github_repo   = cfg.github_repo %}
{% set git_user_name = cfg.git_user_name %}
{% set git_user_email= cfg.git_user_email %}
{% set minion_id     = cfg.minion_id %}
{% set timestamp     = cfg.timestamp %}

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
    - name: {{ grains_dir }}
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
        git config user.name  {{ git_user_name|quote }}
        git config user.email {{ git_user_email|quote }}
        git add {{ grains_file | replace(git_repo_path ~ '/', '') | quote }}
    - cwd: {{ git_repo_path }}
    - require:
      - file: save_grains_file

commit_only_no_push:
  cmd.run:
    - name: |
        set -euo pipefail
        FILE="{{ grains_file | replace(git_repo_path ~ '/', '') }}"
        if ! git diff --cached --quiet -- "$FILE"; then
          git commit -m "Grains changed on {{ minion_id }} ({{ cfg.region }}/{{ cfg.phase }}) at {{ timestamp }}"
        else
          COMMIT_COUNT=$(git log --oneline -- "$FILE" 2>/dev/null | wc -l || echo 0)
          if [ "$COMMIT_COUNT" -eq 0 ]; then
            git commit -m "Initial grains setup for {{ minion_id }} ({{ cfg.region }}/{{ cfg.phase }}) at {{ timestamp }}"
          fi
        fi
    - cwd: {{ git_repo_path }}
    - require:
      - cmd: git_prepare
