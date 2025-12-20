dos2unix file/*
$ssh_port = 22


scp -o ConnectTimeout=60 -P $ssh_port file/* root@148.135.78.131:~
Write-Host "start"
ssh -o ConnectTimeout=60 -p $ssh_port root@148.135.78.131 'cd ~ && chmod +x ./*.sh && ./init.sh'
