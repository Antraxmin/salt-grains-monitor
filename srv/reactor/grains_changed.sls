{% set event_data = data.get('data', {}) %}
{% set minion_id = event_data.get('minion_id', 'UNKNOWN_MINION') %}
{% set timestamp = event_data.get('timestamp', 'N/A') %}

{% set webhook_url = pillar.get('common', {}).get('webhook', {}).get('dooray_url', '') %}
{% set bot_name = pillar.get('common', {}).get('webhook', {}).get('bot_name', 'SaltBot') %}

send_dooray_notification:
  local.http.query:
    - tgt: {{ opts.id }}
    - url: {{ webhook_url }}
    - method: POST
    - data: |
        {
          "text": "**[SALT Grains 변경 알림]**\nMinion ID: **{{ minion_id }}**에서 Grains 파일 변경이 감지되었습니다.\n\n* **감지 시간:** {{ timestamp }}\n* **Minion ID:** {{ minion_id }}",
          "botName": "{{ bot_name }}"
        }
    - header_dict:
        Content-Type: application/json