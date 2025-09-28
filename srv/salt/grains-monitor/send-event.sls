{% from "grains-monitor/map.jinja" import grains_monitor with context %}
{% set minion_id = grains['id'] %}
{% set current_time = none | strftime('%Y-%m-%d %H:%M:%S') %}

ensure_grains_directories:
  file.directory:
    - names:
      - {{ grains_monitor.cache_dir }}
      - {{ grains_monitor.log_dir }}
    - mode: 755
    - makedirs: true

send_grains_event:
  module.run:
    - name: event.fire_master
    - data:
        minion_id: {{ minion_id }}
        timestamp: {{ current_time }}
        event_type: grains_changed
        master_ip: {{ grains_monitor.master_ip }}
        key_grains:
          id: {{ grains.get('id') }}
          os: {{ grains.get('os') }}
          os_family: {{ grains.get('os_family') }}
          kernel: {{ grains.get('kernel') }}
          ip4_interfaces: {{ grains.get('ip4_interfaces', {}) }}
          mem_total: {{ grains.get('mem_total') }}
          num_cpus: {{ grains.get('num_cpus') }}
    - tag: grains/changed
    - require:
      - file: ensure_grains_directories

log_grains_event:
  file.append:
    - name: {{ grains_monitor.log_dir }}/grains-events.log
    - text: |
        [{{ current_time }}] {{ minion_id }} - Grains change event sent
        Master: {{ grains_monitor.master_ip }}
        ---
    - require:
      - module: send_grains_event
      
log_event_sent:
  test.succeed_with_changes:
    - name: "Grains event sent from {{ minion_id }} at {{ current_time }}"
    - require:
      - file: log_grains_event