import os
import sys
import json
import hashlib
import subprocess
import requests
from datetime import datetime
from pathlib import Path
import logging
import salt.config
import salt.utils.event

## Reactor 가 제대로 작동하지 않아서 대신 Reactor 역할을 하는 스크립트 구현
## Minion의 grains 파일이 변경되면 변경사항을 Git에 백업하고 무엇이 바뀌었는지 두레이로 알려주는 역할을 함. 

BACKUP_DIR = "/srv/grains_backup"
GIT_REPO = f"{BACKUP_DIR}/git"
DOORAY_WEBHOOK = "https://nhnent.dooray.com/services/3234962574780345705/4157381524754525194/TQ0PuxJiS5yQYAJwVGn4TA"
LOG_FILE = "/var/log/grains-event-processor.log"

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class GrainsEventProcessor:
    def __init__(self):
        self.backup_dir = Path(BACKUP_DIR)
        self.git_repo = Path(GIT_REPO)
        self.init_git_repo()
        
    # Git 저장소 초기화
    def init_git_repo(self):
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        
        if not (self.git_repo / '.git').exists():
            logger.info(f"Git 저장소를 초기화합니다 : {self.git_repo}")
            self.git_repo.mkdir(parents=True, exist_ok=True)
            # subprocess.run(['git', 'init'], cwd=self.git_repo, check=True)
            # subprocess.run(['git', 'config', 'user.name', 'Antraxmin'], cwd=self.git_repo)
            # subprocess.run(['git', 'config', 'user.email', 'antraxmin@naver.com'], cwd=self.git_repo)
            
            # .gitignore 생성
            gitignore = self.git_repo / '.gitignore'
            gitignore.write_text('*.tmp\n*.swp\n')
            
    # Grains 내용을 파일로 저장
    def save_grains(self, minion_id, grains_content):
        minion_dir = self.git_repo / minion_id
        minion_dir.mkdir(parents=True, exist_ok=True)
        
        grains_file = minion_dir / 'grains'
        grains_file.write_text(grains_content)
        return grains_file
        
    # Git diff 계산
    def get_diff(self, minion_id):
        try:
            result = subprocess.run(
                ['git', 'diff', '--', f'{minion_id}/grains'],
                cwd=self.git_repo,
                capture_output=True,
                text=True
            )
            return result.stdout
        except Exception as e:
            logger.error(f"diff 생성에 실패하였습니다: {e}")
            return ""

    # Git commit    
    def commit_changes(self, minion_id, file_hash):
        try:
            # Stage changes
            subprocess.run(
                ['git', 'add', f'{minion_id}/grains'],
                cwd=self.git_repo,
                check=True
            )
            
            result = subprocess.run(
                ['git', 'diff', '--cached', '--quiet'],
                cwd=self.git_repo
            )
            
            if result.returncode != 0:  # 변경사항 추적 
                commit_msg = f"Grains updated: {minion_id} - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\nHash: {file_hash}"
                subprocess.run(
                    ['git', 'commit', '-m', commit_msg],
                    cwd=self.git_repo,
                    check=True
                )
                logger.info(f"{minion_id}의 변경사항이 커밋되었습니다")
                return True
            else:
                logger.info(f"{minion_id}의 변경사항이 없습니다")
                return False
                
        except Exception as e:
            logger.error(f"commit 실패: {e}")
            return False
            
    # Diff를 두레이 메시지 형식으로 변환
    def format_diff_for_dooray(self, diff_text):
        if not diff_text:
            return "변경사항 없음"
            
        lines = diff_text.split('\n')
        added = []
        removed = []
        
        for line in lines:
            if line.startswith('+') and not line.startswith('+++'):
                content = line[1:].strip()
                if content: 
                    added.append(content)
            elif line.startswith('-') and not line.startswith('---'):
                content = line[1:].strip()
                if content: 
                    removed.append(content)
        
        result = []
        
        if removed:
            result.append("🔴 삭제된 내용: ")
            for item in removed:
                result.append(f"  - {item}")
        
        if added:
            result.append("🟢 추가된 내용")
            for item in added:
                result.append(f"  + {item}")
                
        return '\n'.join(result) if result else "파일 내용 변경"
        
    # 두레이 알림 발송
    def send_dooray_notification(self, minion_id, diff_summary, file_hash):
        try:
            payload = {
                "botName": "SaltStack Grains Monitor",
                "text": f"[Grains 변경] {minion_id}",
                "attachments": [
                    {
                        "title": "변경 내역",
                        "text": diff_summary,
                        "color": "#1E90FF"
                    },
                    {
                        "title": "상세 정보",
                        "text": f"Hash: {file_hash[:8]}\nTime: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                        "color": "#DDDDDD"
                    }
                ]
            }
            
            response = requests.post(
                DOORAY_WEBHOOK,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"{minion_id}의 변경 사항을 두레이로 전송 완료하였습니다")
                return True
            else:
                logger.error(f"두레이 알림 발송에 실패했습니다: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"두레이 알림 발송에 실패했습니다: {e}")
            return False
            
    def process_event(self, event_data):
        try:
            data = event_data.get('data', {})
            minion_id = data.get('minion_id')
            grains_content = data.get('grains_content')
            file_hash = data.get('file_hash')
            
            if not all([minion_id, grains_content, file_hash]):
                logger.warning("이벤트 데이터 수신에 실패하였습니다. ")
                return
                
            logger.info(f"{minion_id}의 Grains 변경 내용을 처리중입니다.")
            self.save_grains(minion_id, grains_content)   #  Grains 저장
            diff = self.get_diff(minion_id) # diff 계산
            has_changes = self.commit_changes(minion_id, file_hash)  # Git commit 
            if has_changes:   # 두레이 알림
                diff_summary = self.format_diff_for_dooray(diff)
                self.send_dooray_notification(minion_id, diff_summary, file_hash)
            else:
                logger.info(f"{minion_id}의 변경사항이 없습니다.")
                
        except Exception as e:
            logger.error(f"이벤트 처리 실패: {e}", exc_info=True)
            
    def run(self):
        logger.info("Starting Grains Event Processor daemon")
        opts = salt.config.client_config('/etc/salt/master')   #  Salt 설정 로드
        event = salt.utils.event.get_event('master', opts=opts)   # 이벤트 버스 연결
        
        try:
            for event_data in event.iter_events(tag='custom/grains/file_changed'):
                self.process_event(event_data)
        except KeyboardInterrupt:
            logger.info("Daemon stopped by user")
        except Exception as e:
            logger.error(f"Daemon error: {e}", exc_info=True)
            raise


if __name__ == '__main__':
    processor = GrainsEventProcessor()
    processor.run()