dos2unix file/*
$ssh_port = 22


scp -o ConnectTimeout=60 -P $ssh_port file/* root@${stun}:~
Write-Host "start"
ssh -o ConnectTimeout=60  root@${stun} 'cd ~ && chmod +x ./*.sh && ./init.sh'
