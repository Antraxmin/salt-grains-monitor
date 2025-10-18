{% set P = salt['pillar.get']('grains_monitor:push', {}) %}
{% set every = P.get('schedule_minutes', 3) %}
{% set splay = P.get('splay_seconds', 15) %}

grains-push-batch:
  schedule.present:
    - function: state.orchestrate
    - job_args: [orch.grains_push_orch]
    - minutes: {{ every }}
    - splay: {{ splay }}
    - maxrunning: 1
