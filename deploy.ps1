dos2unix file/*
$ssh_port = 2200

@($stun, $color, $file) | Foreach-Object -ThrottleLimit 3 -Parallel {
    scp  -P $using:ssh_port file/* root@${_}:~
    ssh  -p $using:ssh_port root@${_} 'chmod +x ~/*.sh && ~/init.sh'
}