send_grains_change_event:
  module.run:
    - name: event.fire_master
    - data:
        minion_id: {{ grains['id'] }}
        file_path: /etc/salt/grains
        timestamp: {{ salt['cmd.run']('date +%s', python_shell=False) }}
        file_hash: {{ salt['cmd.run']('md5sum /etc/salt/grains | awk "{print $1}"', python_shell=True) }}
    - tag: custom/grains/file_changed