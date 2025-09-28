{% set minion_id = data.get('id', 'UNKNOWN_MINION') %}
{% set timestamp = data.get('data', {}).get('timestamp', none | strftime('%Y-%m-%d %H:%M:%S')) %}

{% set webhook_url = pillar.get('common', {}).get('webhook', {}).get('dooray_url') %}  
{% set bot_name = pillar.get('common', {}).get('webhook', {}).get('bot_name', 'SaltBot') %}
{% set text_payload = 'Grains 변경 알림 - Minion: ' ~ minion_id ~ ' - 시간: ' ~ timestamp %}
{% set webhook_payload = {'text': text_payload, 'botName': bot_name} %}

{% if webhook_url %}  
dooray_runner_alert:
  runner.http.query:
    - url: {{ webhook_url }}
    - method: POST
    - data: {{ webhook_payload | json }}
    - header: 'Content-Type: application/json'
    - verify_ssl: False
    
{% else %}
log_missing_url:
  test.succeed_with_changes:
    - name: Missing Dooray webhook URL in pillar (common:webhook:dooray_url)
{% endif %}