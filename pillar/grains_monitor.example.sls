# Example pillar template for Grains Monitor 
grains_monitor:
  # static config (required) 
  git_repo_path: /var/salt/grains-backup
  github_repo: https://github.com/your-org/your-repo.git
  github_token: "Your Github Token"   
  webhook_url: "Your Webhook URL"

  # optional metadata
  region: test
  phase: beta

  # dynamic fields (provided by reactor or inline pillar) 
  minion_id:
  timestamp:
  grains_content:
 
  # Git config 
  git_user_name: "your github name"
  git_user_email: "your github email"
  git_branch: ""
  diff_max_chars: 800