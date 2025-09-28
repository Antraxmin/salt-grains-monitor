{% set current_time = none | strftime('%Y-%m-%d %H:%M:%S') %}
{% set minion_id = grains['id'] %}

{% if grains.id is defined %}

send_grains_data_event:
  module.run:
    - name: event.fire_master
    - data:
        minion_id: {{ minion_id }}
        timestamp: {{ current_time }}
        event_type: grains_file_changed
        all_grains: {{ grains.items() | yaml_encode }} 
        trigger_method: systemd_path_unit
    - tag: grains/changed

{% else %}

log_grains_load_failure:
  test.fail_without_changes:
    - name: "Grains data not available during service execution at {{ current_time }}"

{% endif %}