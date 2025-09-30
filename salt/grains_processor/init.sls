grains_processor_script:
  file.managed:
    - name: /usr/local/bin/grains-event-processor.py
    - source: salt://grains-event-processor.py
    - mode: 755
    - user: root
    - group: root

grains_processor_service:
  file.managed:
    - name: /etc/systemd/system/grains-event-processor.service
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=SaltStack Grains Event Processor
        After=salt-master.service
        Requires=salt-master.service
        
        [Service]
        Type=simple
        ExecStart=/opt/saltstack/salt/bin/python3.10 /usr/local/bin/grains-event-processor.py
        Restart=always
        RestartSec=10
        User=root
        StandardOutput=journal
        StandardError=journal
        
        [Install]
        WantedBy=multi-user.target

grains_backup_directory:
  file.directory:
    - name: /srv/grains_backup
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

reload_systemd_for_processor:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: grains_processor_service

grains_processor_service_running:
  service.running:
    - name: grains-event-processor
    - enable: True
    - require:
      - file: grains_processor_script
      - file: grains_processor_service
      - file: grains_backup_directory
      - cmd: reload_systemd_for_processor
    - watch:
      - file: grains_processor_script
      - file: grains_processor_service