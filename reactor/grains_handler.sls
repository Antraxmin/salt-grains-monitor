{% set minion_id = data['id'] %}
{% set grains_content = data['data']['data'] %}
{% set dooray_webhook = "https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA" %}

init_git:
  local.cmd.run:
    - tgt: salt-master
    - arg:
      - |
        if [ ! -d /srv/grains_backup/git/.git ]; then
          mkdir -p /srv/grains_backup/git
          cd /srv/grains_backup/git
          git init
          git config user.name "Antraxmin"
          git config user.email "antraxmin@naver.com"
        fi

save_grains:
  local.cmd.run:
    - tgt: salt-master
    - arg:
      - |
        mkdir -p /srv/grains_backup/git/{{ minion_id }}
        cat > /srv/grains_backup/git/{{ minion_id }}/grains << 'GRAINS_EOF'
        {{ grains_content }}
        GRAINS_EOF

process_git:
  local.cmd.run:
    - tgt: salt-master
    - arg:
      - |
        cd /srv/grains_backup/git
        git add {{ minion_id }}/grains
        if git commit -m "Update {{ minion_id }} at $(date '+%Y-%m-%d %H:%M:%S')"; then
          DIFF=$(git diff HEAD~1 HEAD -- {{ minion_id }}/grains | grep -E '^[+-]' | grep -v '^[+-]{3}')
          if [ -n "$DIFF" ]; then
            curl -X POST '{{ dooray_webhook }}' \
              -H 'Content-Type: application/json' \
              -d "{\"botName\":\"SaltStack Grains Monitor\",\"text\":\"[Grains 변경] {{ minion_id }}\",\"attachments\":[{\"title\":\"변경 내역\",\"text\":\"$DIFF\",\"color\":\"#1E90FF\"}]}"
          fi
        fi