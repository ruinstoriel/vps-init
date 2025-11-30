dos2unix init.sh nftables.conf id_ed25519.pub nftables-common.local
scp -P 2200 init.sh nftables.conf id_ed25519.pub nftables-common.local root@${color}:~
ssh -p 2200 root@${color} 'chmod +x ~/init.sh && ~/init.sh'
