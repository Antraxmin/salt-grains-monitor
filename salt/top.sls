base:
  '*':
    - grains_monitor
  'salt-master':
    - orch.grains_push_orch
    - scheduler.grains_push