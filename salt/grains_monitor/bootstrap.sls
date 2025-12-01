{% set gm         = salt['pillar.get']('grains_monitor', {}) %}
{% set repo_path  = gm.get('git_repo_path', '/var/salt/grains-backup') %}
{% set branch     = gm.get('git_branch', 'main') %}
{% set remote_url = gm.get('remote_url', '') %}

# Prepare local git directory
repo_root_dir:
  file.directory:
    - name: {{ repo_path }}
    - makedirs: True

git_repo_prepare:
  cmd.run:
    - name: |
        set -e
        if [ ! -d "{{ repo_path }}/.git" ]; then
          git init {{ repo_path }}
        fi
        git -C {{ repo_path }} checkout -B {{ branch }} >/dev/null 2>&1 || true
        if [ -n "{{ remote_url }}" ]; then
          if ! git -C {{ repo_path }} remote | grep -q '^origin$'; then
            git -C {{ repo_path }} remote add origin {{ remote_url }}
          fi
          git -C {{ repo_path }} remote set-url origin {{ remote_url }}
        fi
    - shell: /bin/bash
    - require:
      - file: repo_root_dir

# Push all minions grains to salt-master
# Required for master setup - file_recv: True
push_grains_from_minions:
  cmd.run:
    - name: |
        set -e
        salt --static --out=quiet '*' test.ping >/dev/null 2>&1 || true
        salt --static '*' cp.push /etc/salt/grains
    - shell: /bin/bash
    - require:
      - cmd: git_repo_prepare

# Pull from master cache and place into repo structure
# Cache directory: /var/cache/salt/master/minions/<minion>/files/etc/salt/grains
stage_from_master_cache:
  cmd.run:
    - name: |
        set -e
        REPO="{{ repo_path }}"
        BASE="$REPO/grains"
        CACHE="/var/cache/salt/master/minions"
        mkdir -p "$BASE"

        shopt -s nullglob
        for MDIR in "$CACHE"/*; do
          [ -d "$MDIR" ] || continue
          MID="$(basename "$MDIR")"
          SRC="$MDIR/files/etc/salt/grains"
          [ -f "$SRC" ] || continue

          REGION="$(salt --static --out=newline_values_only "$MID" grains.get region default=unknown 2>/dev/null || echo unknown)"
          PHASE="$(  salt --static --out=newline_values_only "$MID" grains.get phase  default=default 2>/dev/null || echo default)"

          REGION_SAFE="$(printf '%s' "$REGION" | tr -c 'A-Za-z0-9._-' '_' )"
          PHASE_SAFE="$( printf '%s' "$PHASE"  | tr -c 'A-Za-z0-9._-' '_' )"
          MID_SAFE="$(   printf '%s' "$MID"    | tr -c 'A-Za-z0-9._-' '_' )"

          DPATH="$BASE/$REGION_SAFE/$PHASE_SAFE"
          FPATH="$DPATH/$MID_SAFE"
          mkdir -p "$DPATH"

          cp -a "$SRC" "$FPATH"
        done
    - shell: /bin/bash
    - require:
      - cmd: push_grains_from_minions

# Commit on change
git_commit_if_changed:
  cmd.run:
    - name: |
        set -e
        git -C {{ repo_path }} add -A
        if [ -z "$(git -C {{ repo_path }} status --porcelain)" ]; then
          exit 0
        fi
        if git -C {{ repo_path }} rev-parse --verify HEAD >/dev/null 2>&1; then
          git -C {{ repo_path }} commit -m "Update grains snapshot"
        else
          git -C {{ repo_path }} commit -m "Initial backup of /etc/salt/grains"
        fi
    - shell: /bin/bash
    - require:
      - cmd: stage_from_master_cache

# Push only during initial setup
git_push_if_needed:
  cmd.run:
    - name: |
        set -e
        if ! git -C {{ repo_path }} remote | grep -q '^origin$'; then
          exit 0
        fi
        if [ -z "{{ remote_url }}" ]; then
          exit 0
        fi
        if git -C {{ repo_path }} rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
          git -C {{ repo_path }} push origin HEAD:refs/heads/{{ branch }}
        else
          git -C {{ repo_path }} push -u origin HEAD:refs/heads/{{ branch }}
        fi
    - env:
        HOME: /root
        GIT_TERMINAL_PROMPT: '0'
    - shell: /bin/bash
    - require:
      - cmd: git_commit_if_changed
