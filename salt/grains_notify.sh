#!/bin/bash
/usr/bin/salt-call grains_event.send_change_event

curl -X POST 'https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA' \
  -H 'Content-Type: application/json' \
  -d "{\"botName\":\"SaltStack\",\"text\":\"Grains 변경: $(hostname)\"}"
