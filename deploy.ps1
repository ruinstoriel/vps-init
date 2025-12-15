dos2unix file/*
$ssh_port = 2200

@( $stun) | Foreach-Object -ThrottleLimit 3 -Parallel {
    scp  -P $using:ssh_port file/* root@${_}:~
    Write-Host "开始执行脚本"
    ssh  -p $using:ssh_port root@${_} 'cd ~ && chmod +x ./*.sh && ./init.sh'
}