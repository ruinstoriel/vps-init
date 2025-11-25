dos2unix init.sh nftables.conf
scp -P 2200 init.sh nftables.conf root@${color}:~
ssh -p 2200 root@${color} '~/init.sh'
