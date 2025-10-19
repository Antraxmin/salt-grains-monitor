{% set P = salt['pillar.get']('grains_monitor:push', {}) %}
{% set every = P.get('schedule_seconds', 10) %}  
{% set splay = P.get('splay_seconds', 3) %}      

grains-push-batch:
  schedule.present:
    - function: state.orchestrate
    - job_kwargs:
        mods: orch.grains_push_orch
    - seconds: {{ every }}   
    - splay: {{ splay }}
    - maxrunning: 1
    - enabled: True
