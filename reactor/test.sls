{% set dooray_msg = "https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA" %}
{% set message = {
    "botName": "%s" % (data['id']),
    "text": "%s" % (data['data']['data'])
} %}

send_message:
  runner.http.query:
    - arg:
      - {{ dooray_msg }}
    - kwarg:
        method: POST
        header_dict:
          Content-Type: application/json
        data: '{{ message|json }}'