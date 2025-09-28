{% set minion_id = data.get('id', 'UNKNOWN_MINION') %}
{% set event_data = data.get('data', {}) %}
{% set timestamp = event_data.get('timestamp', none | strftime('%Y-%m-%d %H:%M:%S')) %}

{% set webhook_url = pillar.get('common', {}).get('webhook', {}).get('dooray_url', '') %}
{% set bot_name = pillar.get('common', {}).get('webhook', {}).get('bot_name', 'SaltBot') %}

send_dooray_notification:
  runner.http.query:
    - url: {{ webhook_url }}
    - method: POST
    - data: '{"text":"**[SALT Grains 변경 알림]**\nMinion: {{ minion_id }}\n시간: {{ timestamp }}","botName":"{{ bot_name }}"}'
    - header_dict:
        Content-Type: application/json