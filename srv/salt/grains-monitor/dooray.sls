{% set minion_id = grains.get('id', 'UNKNOWN_MINION') %}
{% set timestamp = none | strftime('%Y-%m-%d %H:%M:%S') %}

send_dooray_notification:
  cmd.run:
    - name: 'curl -X POST -H "Content-Type: application/json" -d "{\"text\":\"Grains 변경 알림\\nMinion: {{ minion_id }}\\n시간: {{ timestamp }}\",\"botName\":\"SaltBot\"}" "https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA"'

log_dooray_sent:
  file.append:
    - name: /var/log/grains-monitor/dooray-notifications.log
    - text: "[{{ timestamp }}] {{ minion_id }} - Dooray notification sent"
    - require:
      - cmd: send_dooray_notification