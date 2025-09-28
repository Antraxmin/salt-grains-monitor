include:
  - grains-monitor.systemd-watcher

grains_monitor_initialization:
  test.succeed_with_changes:
    - name: "Grains monitoring system initialized on {{ grains['id'] }}"
    - require:
      - sls: grains-monitor.systemd-watcher

grains_monitor_init_status:  
  grains.present:
    - name: grains_monitor_initialized
    - value:
        status: completed
        minion_id: {{ grains['id'] }}
        initialized_at: {{ none | strftime('%Y-%m-%d %H:%M:%S') }}
        version: "1.0.0"
    - force: True
    - require:
      - test: grains_monitor_initialization