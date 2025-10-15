# grains/changed 이벤트 태그 날아왔을때 반응할 Reactor
# 이벤트에서 전달되는 전체 Grains 데이터를 Custom State에 넘겨주기 
     # 1. Git 백업하는 기능 
     # 2. Git diff로 실제 변경된 내용 구해서 Dooray Webhook으로 전달하는 기능
     # 위 두 기능을 분리된 State로 구현해도 되고, 하나의 State로 통합해도됨 
     # Master에도 Minion 설치했기 때문에 위의 State는 모두 salt-master에서 실행되도록 

backup_and_notify_grains:
  local.state.apply:
    - tgt: salt-master
    - arg:
      - grains_monitor.backup_notify
    - kwarg:
        pillar:
          minion_id: {{ data['id'] }}
          timestamp: {{ data['_stamp'] }}
          grains_content: |
            {{ data.get('data', {}).get('data', '') | indent(12) }}
        queue: True