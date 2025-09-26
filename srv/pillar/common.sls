common:
  master_ip: "192.168.0.98"
  
  paths:
    backup_base: "/backup/grains"
    log_dir: "/var/log/grains-monitor"
    temp_dir: "/tmp/grains-monitor"
    cache_dir: "/var/cache/grains"
  
  webhook:
    dooray_url: "https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA"
    bot_name: "Salt Grains Monitor"
    bot_icon: "https://cdn-icons-png.flaticon.com/512/2103/2103633.png"
    timeout: 30
  
  systemd:
    path_unit_name: "grains-monitor"
    watch_paths:
      - "/etc/salt/grains.d"
      - "/etc/salt/grains"
      - "/etc/salt/minion"
      - "/srv/salt/_grains"