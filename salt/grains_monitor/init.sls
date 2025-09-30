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
        ExecStart=/bin/bash -c 'GRAINS_B64=$(cat /etc/salt/grains | base64 -w 0); salt-call event.send "grains/change" data="{\"grains_base64\":\"$GRAINS_B64\", \"minion_id\":\"$(salt-call --local grains.get id --out=newline_values_only)\"}"'
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