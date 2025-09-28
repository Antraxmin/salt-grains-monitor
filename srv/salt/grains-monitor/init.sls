{% from "grains-monitor/map.jinja" import grains_monitor with context %}
{% set unit_name = grains_monitor.unit_name %}

# Grains 경로를 감시할 Systemd path unit 파일 생성 
grains_monitor_path_unit:
  file.managed:
    - name: /etc/systemd/system/{{ unit_name }}.path
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=Monitor Salt Grains Changes
        After=salt-minion.service
        
        [Path]
        {% for path in grains_monitor.watch_paths %}
        PathModified={{ path }}
        {% endfor %}
        
        Unit={{ unit_name }}.service
        
        [Install]
        WantedBy=multi-user.target

# 변경 감지 후 실행될 Systemd service unit 파일 생성
grains_monitor_service_unit:
  file.managed:
    - name: /etc/systemd/system/{{ unit_name }}.service
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=Salt Grains Change Handler
        After=salt-minion.service
        
        [Service]
        Type=oneshot
        ExecStart=/usr/bin/salt-call state.sls grains-monitor.send-event
        User={{ grains_monitor.service_user }}
        Group={{ grains_monitor.service_user }}
        StandardOutput=journal
        StandardError=journal
        TimeoutSec={{ grains_monitor.timeout }}
        
        [Install]
        WantedBy=multi-user.target
    - require:
      - file: grains_monitor_path_unit

# systemd reload
grains_monitor_systemd_reload:
  module.run:
    - name: service.systemctl_reload
    - onchanges:
      - file: grains_monitor_path_unit
      - file: grains_monitor_service_unit

# Path unit 활성화 및 실행
grains_monitor_path_active:
  service.running:
    - name: {{ unit_name }}.path
    - enable: True
    - require:
      - module: grains_monitor_systemd_reload
      - file: grains_monitor_service_unit 