{% set C = salt['pillar.get']('grains_monitor', {}) %}
{% set repo = C.get('git_repo_path', '/var/lib/grains-backup') %}
{% set branch = C.get('git_branch', 'main') %}
{% set gh = C.get('github_https_base', '') %}
{% set wh = C.get('dooray_webhook_url', C.get('webhook_url', '')) %}
{% set P = C.get('push', {}) %}
{% set minc = P.get('min_commits', 1) %}
{% set maxage = P.get('max_age', 300) %}
{% set maxcomm = P.get('max_commits_per_batch', 50) %}
{% set diffmax = P.get('diff_max_chars', C.get('diff_max_chars', 2000)) %}

{% set state_dir = '/var/lib/salt-grains-monitor' %}
{% set last_ref_f = state_dir + '/last_ref' %}
{% set last_ts_f = state_dir + '/last_ts' %}

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

calc-to-push:
  salt.function:
    - name: cmd.run_stdout
    - tgt: 'salt-master'
    - kwarg:
        cmd: "git -C {{ repo }} rev-list --count origin/{{ branch }}..HEAD || echo 0"
        python_shell: True

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

{% set _exists = salt['file.file_exists'](last_ref_f) %}
{% set _raw = salt['file.read'](last_ref_f) if _exists else '' %}
{% set base_ref = (_raw.strip() if _raw and _raw.strip() else 'origin/' ~ branch) %}
{% set last_ts = (salt['file.read'](last_ts_f) if salt['file.file_exists'](last_ts_f) else '0')|int %}
{% set now_ts = salt['cmd.run_stdout']('date +%s')|int %}
{% set age = now_ts - last_ts %}
{% set to_push = (salt['cmd.run_stdout']('git -C {} rev-list --count origin/{}..HEAD || echo 0'.format(repo, branch)) or '0')|int %}
{% set do_push = (to_push >= minc) or (age >= maxage) %}

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

{% set rows = salt['cmd.run_stdout'](
  'git -C {} log --no-merges --pretty="%H|%s" --reverse {}..HEAD -- \'grains/*/*/*\' || true'
  .format(repo, base_ref)
).splitlines() %}
{% set have_wh = wh|default('', true) %}

{% set N = rows|length %}
{% set link_only_threshold = salt['pillar.get']('grains_monitor:notify:link_only_threshold', 10) %}  

{% if have_wh and N > 0 %}

{% if N <= link_only_threshold %}
  {% for row in rows[:maxcomm] %}
  {% set parts = row.split('|', 1) %}
  {% set h = parts[0] %}
  {% set subj = parts[1] if parts|length > 1 else '(no subject)' %}

commit-{{ h[:7] }}-notify:
  salt.function:
    - name: http.query
    - tgt: 'salt-master'
    - kwarg:
        url: {{ wh }}
        method: POST
        header_dict: {'Content-Type': 'application/json'}
        status: True
        text: True
        decode: True
        data: |
          {{ salt['slsutil.serialize']('json', {
            'botName': 'grains-batch',
            'text': (
              '- [' ~ h[:7] ~ '](' ~ gh ~ '/commit/' ~ h ~ ') **' ~ subj ~ '**\n' ~
              '```diff\n' ~ (
                (salt['cmd.run_stdout'](
                  "git -C {} diff --no-color --unified=0 --no-prefix {}^! -- 'grains/*/*/*' | "
                  "grep -E '^[+-][^+-]' || true".format(repo, h)
                ) or '(no +/- lines under grains/*/*/*)')[:diffmax]
              ) ~ '\n```'
            )
          }) }}
    - require:
      - salt: collect-commits
  {% endfor %}

{% else %}

{% set ns = namespace(lines=[]) %}
{% for row in rows[:maxcomm] %}
  {% set parts = row.split('|', 1) %}
  {% set h = parts[0] %}
  {% set subj = parts[1] if parts|length > 1 else '(no subject)' %}
  {% set _ = ns.lines.append('- [{}]({}/commit/{}) **{}**'.format(h[:7], gh, h, subj)) %}
{% endfor %}
{% set more = '…and {} more.'.format(N - maxcomm) if N > maxcomm else '' %}
{% set batch_text = '**Pushed {} commit(s) to {}**\n\n{}\n{}'.format(
  N, branch, '\n'.join(ns.lines), more
) if ns.lines else '**Pushed {} commit(s) to {}**'.format(N, branch) %}

batch-links-notify:
  salt.function:
    - name: http.query
    - tgt: 'salt-master'
    - kwarg:
        url: {{ wh }}
        method: POST
        header_dict: {'Content-Type': 'application/json'}
        status: True
        text: True
        decode: True
        data: |
          {{ salt['slsutil.serialize']('json', {
            'botName': 'grains-batch',
            'text': batch_text
          }) }}
    - require:
      - salt: collect-commits
{% endif %}


{% endif %}

write-last-ref:
  salt.function:
    - name: file.write
    - tgt: 'salt-master'
    - kwarg:
        path: {{ last_ref_f }}
        contents: {{ salt['cmd.run_stdout']('git -C {} rev-parse HEAD'.format(repo)) }}
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