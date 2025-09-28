{% from "grains-monitor/map.jinja" import grains_monitor with context %}

grains_monitor_directories:
  file.directory:
    - names:
      - {{ grains_monitor.cache_dir }}
      - {{ grains_monitor.log_dir }}
      - {{ grains_monitor.temp_dir }}
      - {{ grains_monitor.backup_dir }}/{{ grains['id'] }}
    - mode: 755
    - makedirs: true
    - user: {{ grains_monitor.service_user }}
    - group: {{ grains_monitor.service_user }}

grains_monitor_path_unit:
  file.managed:
    - name: /etc/systemd/system/{{ grains_monitor.unit_name }}.path
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=Monitor Salt Grains Changes
        Documentation=Salt grains monitoring path unit
        After=salt-minion.service
        
        [Path]
        {% for path in grains_monitor.watch_paths %}
        PathModified={{ path }}
        {% endfor %}
        
        Unit={{ grains_monitor.unit_name }}.service
        
        [Install]
        WantedBy=multi-user.target
    - require:
      - file: grains_monitor_directories

grains_monitor_service_unit:
  file.managed:
    - name: /etc/systemd/system/{{ grains_monitor.unit_name }}.service
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=Salt Grains Change Handler
        Documentation=Salt grains change processing service
        After=salt-minion.service
        Wants=salt-minion.service
        
        [Service]
        Type=oneshot
        ExecStart=/usr/bin/salt-call --local state.sls grains-monitor.send-event
        User={{ grains_monitor.service_user }}
        Group={{ grains_monitor.service_user }}
        StandardOutput=journal
        StandardError=journal
        TimeoutSec={{ grains_monitor.timeout }}
        
        ExecStartPre=/bin/sleep 0.5
        
        [Install]
        WantedBy=multi-user.target
    - require:
      - file: grains_monitor_path_unit

grains_monitor_systemd_reload:
  module.run:
    - name: service.systemctl_reload
    - onchanges:
      - file: grains_monitor_path_unit
      - file: grains_monitor_service_unit

{% if grains_monitor.enabled %}
grains_monitor_path_active:
  service.running:
    - name: {{ grains_monitor.unit_name }}.path
    - enable: True
    - require:
      - module: grains_monitor_systemd_reload

record_grains_monitor_status:
  grains.present:
    - name: grains_monitor_config
    - value:
        enabled: {{ grains_monitor.enabled }}
        unit_name: {{ grains_monitor.unit_name }}
        watch_paths: {{ grains_monitor.watch_paths }}
        cache_dir: {{ grains_monitor.cache_dir }}
        log_dir: {{ grains_monitor.log_dir }}
        webhook_url: {{ grains_monitor.webhook_url }}
        master_ip: {{ grains_monitor.master_ip }}
        configured_at: {{ none | strftime('%Y-%m-%d %H:%M:%S') }}
        method: systemd_path_unit
        service_user: {{ grains_monitor.service_user }}
    - force: True
    - require:
      - service: grains_monitor_path_active

{% else %}

grains_monitor_path_inactive:
  service.dead:
    - name: {{ grains_monitor.unit_name }}.path
    - enable: False

grains_monitor_disabled_status:
  grains.present:
    - name: grains_monitor_config
    - value:
        enabled: False
        disabled_at: {{ none | strftime('%Y-%m-%d %H:%M:%S') }}
        reason: disabled_in_pillar
    - force: True
    - require:
      - service: grains_monitor_path_inactive
{% endif %}