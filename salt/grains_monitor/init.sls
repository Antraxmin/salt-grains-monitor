sync_grains_event_module:
  module.run:
    - name: saltutil.sync_modules

grains_notify_script:
  file.managed:
    - name: /usr/local/bin/grains-notify.sh
    - source: salt://grains_notify.sh
    - mode: 755
    - user: root
    - group: root

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
        Wants=salt-minion.service
        
        [Service]
        Type=oneshot
        ExecStartPre=/bin/sleep 0.5
        ExecStart=/usr/local/bin/grains-notify.sh
        User=root
        Group=root
        StandardOutput=journal
        StandardError=journal
        TimeoutSec=30
        
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
        PathModified=/etc/salt/grains.d
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