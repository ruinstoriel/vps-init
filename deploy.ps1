dos2unix file/*
$ssh_port = 2200


scp -o ConnectTimeout=60 -P $ssh_port file/* root@${stun}:~
Write-Host "start"
ssh -o ConnectTimeout=60  -p $ssh_port root@${stun} 'cd ~ && chmod +x ./*.sh && ./init.sh'
