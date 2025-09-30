grains_monitor_service_file:
  file.managed:
    - name: /etc/systemd/system/grains-monitor.service
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=Salt Grains Change Handler
        After=salt-minion.service
        
        [Service]
        Type=oneshot
        ExecStartPre=/bin/sleep 0.5
        ExecStart=/usr/bin/python3 -c "import subprocess, json; data=open('/etc/salt/grains').read(); subprocess.run(['salt-call', 'event.send', 'grains/change', 'data=' + json.dumps({'data': data})])"
        User=root
        StandardOutput=journal
        StandardError=journal
        
        [Install]
        WantedBy=multi-user.target

grains_monitor_path_file:
  file.managed:
    - name: /etc/systemd/system/grains-monitor.path
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=Monitor Salt Grains File Changes
        After=salt-minion.service
        
        [Path]
        PathModified=/etc/salt/grains
        Unit=grains-monitor.service
        
        [Install]
        WantedBy=multi-user.target

reload_systemd_daemon:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: grains_monitor_service_file
      - file: grains_monitor_path_file

grains_monitor_path_service:
  service.running:
    - name: grains-monitor.path
    - enable: True
    - require:
      - file: grains_monitor_path_file
      - cmd: reload_systemd_daemon