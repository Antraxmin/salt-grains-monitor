{% from "grains-monitor/map.jinja" import grains_monitor with context %}
{% set minion_id = grains['id'] %}
{% set current_time = none | strftime('%Y-%m-%d %H:%M:%S') %}

ensure_grains_cache_directory:
  file.directory:
    - name: {{ grains_monitor.cache_dir }}
    - mode: 755
    - makedirs: true

send_grains_event:
  module.run:
    - name: event.fire_master
    - m_data:
        minion_id: {{ minion_id }}
        timestamp: {{ current_time }}
        event_type: grains_changed
        master_ip: {{ grains_monitor.master_ip }}
        key_grains:
          id: {{ grains.get('id') }}
          os: {{ grains.get('os') }}
          os_family: {{ grains.get('os_family') }}
          ip4_interfaces: {{ grains.get('ip4_interfaces', {}) }}
    - m_tag: grains/changed
    - require:
      - file: ensure_grains_cache_directory

log_grains_event_sent:
  test.succeed_with_changes:
    - name: "Grains event sent from {{ minion_id }} at {{ current_time }}"
    - require:
      - module: send_grains_event