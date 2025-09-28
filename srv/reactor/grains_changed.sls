send_notification:
  salt.state:
    - tgt: {{ data.get('id', '*') }}
    - sls: grains-monitor.dooray