{% from "grains-monitor/map.jinja" import grains_monitor with context %}
{% set minion_id = grains['id'] %}
{% set current_time = none | strftime('%Y-%m-%d %H:%M:%S') %}

{% set current_grains = salt['grains.items']() %}
{% set hash_file = grains_monitor.cache_dir + '/current.hash' %}
{% set current_hash = current_grains | string | sha256 %}

{% set grains_files = salt['file.find']('/etc/salt/grains.d', name='*.conf', type='f') %}
{% set grains_d_hash = grains_files | join('') | sha256 %}

ensure_grains_cache_directory:
  file.directory:
    - name: {{ grains_monitor.cache_dir }}
    - mode: 755
    - makedirs: true

check_grains_change:
  cmd.run:
    - name: |
        HASH_FILE="{{ hash_file }}"
        CURRENT_HASH="{{ current_hash }}"
        GRAINS_D_HASH="{{ grains_d_hash }}"
        
        PREVIOUS_HASH=""
        PREVIOUS_GRAINS_D_HASH=""
        
        if [ -f "$HASH_FILE" ]; then
          PREVIOUS_HASH=$(head -n1 "$HASH_FILE")
          PREVIOUS_GRAINS_D_HASH=$(tail -n1 "$HASH_FILE" 2>/dev/null || echo "")
        fi
        
        if [ "$CURRENT_HASH" = "$PREVIOUS_HASH" ] && [ "$GRAINS_D_HASH" = "$PREVIOUS_GRAINS_D_HASH" ]; then
          echo "No grains changes detected"
          exit 1
        fi
        
        echo "$CURRENT_HASH" > "$HASH_FILE"
        echo "$GRAINS_D_HASH" >> "$HASH_FILE"
        
        echo "Hash updated: previous=$PREVIOUS_HASH current=$CURRENT_HASH"
    - stateful: True
    - require:
      - file: ensure_grains_cache_directory

send_detailed_grains_event:
  module.run:
    - name: event.fire_master
    - m_data:
        minion_id: {{ minion_id }}
        timestamp: {{ current_time }}
        event_type: grains_changed
        master_ip: {{ grains_monitor.master_ip }}
        
        grains_hash: {{ current_hash }}
        grains_d_hash: {{ grains_d_hash }}
        
        key_grains:
          id: {{ grains.get('id') }}
          os: {{ grains.get('os') }}
          os_family: {{ grains.get('os_family') }}
          ip4_interfaces: {{ grains.get('ip4_interfaces', {}) }}
          
    - m_tag: grains/changed
    - require:
      - cmd: check_grains_change

log_grains_event_sent:
  test.succeed_with_changes:
    - name: "Grains change event successfully sent from {{ minion_id }} at {{ current_time }}"
    - require:
      - module: send_detailed_grains_event