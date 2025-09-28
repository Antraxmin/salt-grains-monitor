{% set event_data = data.get('data', {}) %}
{% set minion_id = event_data.get('minion_id', 'UNKNOWN_MINION') %}
{% set timestamp = event_data.get('timestamp', 'N/A') %}
{% set trigger = event_data.get('trigger_method', 'Manual/Watch') %}
{% set all_grains = event_data.get('all_grains', {}) %}

{% set webhook_url = pillar.get('common', {}).get('webhook', {}).get('dooray_url', 'DEFAULT_URL_REQUIRED') %}
{% set bot_name = pillar.get('common', {}).get('webhook', {}).get('bot_name', 'SaltBot') %}

{% set webhook_data_text = '
**[SALT Grains 변경 알림]** 
Minion ID: **' ~ minion_id ~ '** 에서 Grains 파일 변경이 감지되었습니다.

* **감지 시간:** ' ~ timestamp ~ '
* **트리거:** ' ~ trigger ~ '
---
**Minion 전체 Grains 데이터:**
```json
' ~ all_grains | json | truncate(2500, killwords=True, end='...\n```')
%}

{% set webhook_payload = {
    'text': webhook_data_text,
    'botName': bot_name 
} %}

send_dooray_notification:
  module.run:
    - name: http.query
    - url: {{ webhook_url }}
    - method: POST
    - data: {{ webhook_payload | json }}
    - header: 'Content-Type: application/json'
    - verify_ssl: True