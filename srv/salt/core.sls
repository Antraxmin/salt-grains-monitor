packages:
  pkg.installed:
    - pkgs:
      - git
      - curl
      - jq
      - systemd

salt_directories:
  file.directory:
    - names:
      - /etc/salt/grains.d
      - /var/cache/salt
      - /var/log/salt
    - makedirs: true
    - mode: 755

salt_minion_service:
  service.running:
    - name: salt-minion
    - enable: true