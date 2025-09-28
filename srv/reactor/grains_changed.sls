{% set minion_id = data.get('id', 'UNKNOWN_MINION') %}
{% set event_data = data.get('data', {}) %}
{% set timestamp = event_data.get('timestamp', none | strftime('%Y-%m-%d %H:%M:%S')) %}

{% set webhook_url = pillar.get('common', {}).get('webhook', {}).get('dooray_url', '') %}
{% set bot_name = pillar.get('common', {}).get('webhook', {}).get('bot_name', 'SaltBot') %}

send_dooray_notification:
  http.query:
    - name: https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA
    - method: POST
    - data: '{"text":"Grains 변경 알림 - Minion: {{ minion_id }} - 시간: {{ timestamp }}","botName":"{{ bot_name }}"}'
    - header_dict:
        Content-Type: application/json
    - status: 200