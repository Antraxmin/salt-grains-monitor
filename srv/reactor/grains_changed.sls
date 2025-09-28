{% set minion_id = data.get('id', 'UNKNOWN_MINION') %}
{% set event_data = data.get('data', {}) %}
{% set timestamp = event_data.get('timestamp', none | strftime('%Y-%m-%d %H:%M:%S')) %}

{% set webhook_url = pillar.get('common', {}).get('webhook', {}).get('dooray_url', 'DEFAULT_URL_REQUIRED') %}
{% set bot_name = pillar.get('common', {}).get('webhook', {}).get('bot_name', 'SaltBot') %}

{% set webhook_payload = {
    'text': 'Grains 변경 알림 - Minion: ' ~ minion_id ~ ' - 시간: ' ~ timestamp,
    'botName': bot_name
} %}

- name: dooray_alert
  fun: http.query
  client: local
  args:
    - url: {{ webhook_url }}
    - method: POST
    - data: {{ webhook_payload | json }}
    - header: 'Content-Type: application/json'
    - verify_ssl: False 