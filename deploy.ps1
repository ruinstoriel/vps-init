dos2unix init.sh nftables.conf id_ed25519.pub
scp init.sh nftables.conf id_ed25519.pub root@${color}:~
ssh root@${color} 'chmod +x ~/init.sh && ~/init.sh'
