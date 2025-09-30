import hashlib
import time
import logging
import os

log = logging.getLogger(__name__)

__virtualname__ = 'grains_event'


# Salt가 이 모듈을 로드할지 결정하는 함수
def __virtual__():
    return __virtualname__

# Grains 변경 이벤트를 Salt Master의 이벤트 버스로 전송하는 함수
def send_change_event(name='grain_changed'):
    minion_id = __grains__.get('id', 'unknown')   # 전역 변수 grains에서 minion ID를 가져온다. 
    grains_file = '/etc/salt/grains'  # Minion의 grains 파일 경로 

    if not os.path.exists(grains_file):   # grains 파일이 실제로 존재하는지 확인
        log.warning(f"Grains 파일이 존재하지 않음: {grains_file}")
        return {
            'result': False,
            'comment': f'Grains 파일이 존재하지 않음: {grains_file}'
        }
    
    try:   # 파일 내용 읽어서 해시값을 계산
        with open(grains_file, 'r') as f:
            grains_content = f.read()
        
        file_hash = hashlib.md5(grains_content.encode()).hexdigest()
        log.info(f"{minion_id}의 grains 파일 내용을 읽음. 해시: {file_hash}")
        
    except Exception as e:
        log.error(f"grains 파일 읽기 실패: {e}")
        return {
            'result': False,
            'comment': f'grains 파일 읽기 실패: {str(e)}'
        }

    # Salt 이벤트에 담아 보낼 데이터 
    event_data = {
        'minion_id': minion_id,
        'file_path': grains_file,
        'file_hash': file_hash,
        'grains_content': grains_content,
        'timestamp': str(int(time.time()))
    }
    
    try:   # 데이터 전송 
        result = __salt__['event.send'](   #  event.send 호출
            'custom/grains/file_changed',
            event_data
        )
        
        log.info(f"Grains 변경 이벤트 전송 완료 -  {minion_id}")
        
        return {
            'result': True,
            'changes': {'event_sent': event_data},
            'comment': f'미니언 {minion_id}에 대해 grains 변경 이벤트 전송 성공'
        }
        
    except Exception as e:
        log.error(f"이벤트 전송 실패: {e}")
        return {
            'result': False,
            'comment': f'이벤트 전송 실패: {str(e)}'
        }


# /etc/salt/grains 파일의 현재 상태 정보를 조회
def get_grains_info():
    minion_id = __grains__.get('id', 'unknown')
    grains_file = '/etc/salt/grains'
    
    if not os.path.exists(grains_file):
        return {
            'result': False,
            'comment': 'Grains 파일이 존재하지 않음'
        }
    
    try:
        with open(grains_file, 'r') as f:
            content = f.read()
        
        file_hash = hashlib.md5(content.encode()).hexdigest()  # 파일 내용 해시값 계산 
        file_stat = os.stat(grains_file)
        
        # 파일 정보를 딕셔너리로 반환
        return {
            'result': True,
            'minion_id': minion_id,
            'file_path': grains_file,
            'file_hash': file_hash,
            'file_size': file_stat.st_size,
            'modified_time': time.ctime(file_stat.st_mtime)
        }
        
    except Exception as e:
        return {
            'result': False,
            'comment': str(e)
        }