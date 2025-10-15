backup_and_notify_grains:
  local.state.apply:
    - tgt: salt-master
    - arg:
      - grains_monitor.backup_notify
    - kwarg:
        pillar:
          minion_id: {{ data['id'] }}
          timestamp: {{ data['_stamp'] }}
          grains_content: |
            {{ data.get('data', {}).get('data', '') | indent(12) }}
        queue: True